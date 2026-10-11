#!/bin/bash
# Check versioning and build failures without accessing Mail or credentials.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/scripts.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/script"
cp script/version "${scratch}/script/version"
git -C "${scratch}" init -q -b main
git -C "${scratch}" -c user.name=Fixture -c user.email=fixture@example.test \
  -c commit.gpgsign=false commit -q --allow-empty -m Fixture
[[ "$("${scratch}/script/version")" == $'0.0.0\n1' ]] || exit 1
git -C "${scratch}" tag 1.2.3
[[ "$("${scratch}/script/version")" == $'1.2.3\n1' ]] || exit 1
git -C "${scratch}" update-ref refs/remotes/origin/main HEAD
git -C "${scratch}" -c user.name=Fixture -c user.email=fixture@example.test \
  -c commit.gpgsign=false commit -q --allow-empty -m Second
[[ "$("${scratch}/script/version")" == $'1.2.3\n1' ]] || exit 1
"${scratch}/script/version" --xcconfig "${scratch}/.build/version.xcconfig"
grep -q '^MARKETING_VERSION = 1.2.3$' "${scratch}/.build/version.xcconfig"
grep -q '^CURRENT_PROJECT_VERSION = 1$' "${scratch}/.build/version.xcconfig"
git -C "${scratch}" tag v2.0.0
if "${scratch}/script/version" &>/dev/null; then
  echo 'Invalid version tag was accepted' >&2
  exit 1
fi
git -C "${scratch}" tag -d v2.0.0 &>/dev/null
echo 'Version script tests passed'

cp script/bootstrap script/build "${scratch}/script/"
mkdir -p "${scratch}/bin" "${scratch}/MailSearch.xcodeproj" \
  "${scratch}/.DerivedData/Build/Products/Release/MailSearch.app"
touch "${scratch}/Package.resolved"
for command in brew xcodegen python3 codesign; do
  printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/${command}"
done
printf '#!/bin/bash\nexit 99\n' >"${scratch}/script/prepare"
cat >"${scratch}/bin/xcodebuild" <<'BUILDER'
#!/bin/bash
echo 'Build diagnostic on stdout'
echo 'Build diagnostic on stderr' >&2
exit "${BUILD_TEST_STATUS}"
BUILDER
chmod +x "${scratch}/bin/"* "${scratch}/script/"*
export PATH="${scratch}/bin:${PATH}"
"${scratch}/script/bootstrap"
echo 'Bootstrap does not resolve Swift packages'
printf '#!/bin/bash\nexit 0\n' >"${scratch}/script/prepare"
export XCODE_CONFIGURATION=Release
export BUILD_TEST_STATUS=65
if "${scratch}/script/build" >"${scratch}/failure.log" 2>&1; then
  echo 'Build failure was hidden by an existing app bundle' >&2
  exit 1
fi
export BUILD_TEST_STATUS=0
"${scratch}/script/build" >"${scratch}/success.log" 2>&1
for log in failure success; do
  for stream in stdout stderr; do
    grep -q "Build diagnostic on ${stream}" "${scratch}/${log}.log"
  done
done
echo 'Build script tests passed'

cp script/package "${scratch}/script/package"
cat >"${scratch}/bin/security" <<'SECURITY'
#!/bin/bash
printf '%s\n' "${NOTARIZATION_KEY}" | "${PACKAGE_TEST_KEY_VALIDATOR}" "${PACKAGE_TEST_KEY}" || exit 68
touch "${PACKAGE_TEST_SECURITY}"
if [[ "$1" == list-keychains ]]; then
  echo '"fixture.keychain-db"'
  exit 0
fi
exit 67
SECURITY
chmod +x "${scratch}/bin/security"
cat >"${scratch}/validate-key.swift" <<'SWIFT'
import CryptoKit
import Foundation

guard let pem = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8),
      let key = try? P256.Signing.PrivateKey(pemRepresentation: pem),
      let original = try? P256.Signing.PrivateKey(pemRepresentation:
          String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)),
      key.publicKey.rawRepresentation == original.publicKey.rawRepresentation else { exit(1) }
SWIFT
export PACKAGE_TEST_KEY_VALIDATOR="${scratch}/validate-key"
export PACKAGE_TEST_KEY="${scratch}/fixture.p8"
swiftc "${scratch}/validate-key.swift" -o "${PACKAGE_TEST_KEY_VALIDATOR}"
export PACKAGE_TEST_SECURITY="${scratch}/security-called"
export DEVELOPER_ID_APPLICATION_CERTIFICATE=fixture
export DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD=fixture
export NOTARIZATION_KEY_ID=fixture
export NOTARIZATION_ISSUER_ID=fixture
/usr/bin/openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 \
  -out "${scratch}/fixture.p8" &>/dev/null
for format in pem unwrapped crlf base64 escaped filename malformed; do
  case "${format}" in
  pem) NOTARIZATION_KEY="$(cat "${scratch}/fixture.p8")" ;;
  unwrapped) NOTARIZATION_KEY="$(awk '/^-----/ {if (NR > 1) printf "\n"; print; next} {printf "%s", $0}' "${scratch}/fixture.p8")" ;;
  crlf) NOTARIZATION_KEY="$(sed $'s/$/\r/' "${scratch}/fixture.p8")" ;;
  base64) NOTARIZATION_KEY="$(base64 <"${scratch}/fixture.p8")" ;;
  escaped) NOTARIZATION_KEY="$(awk '{printf "%s\\n", $0}' "${scratch}/fixture.p8")" ;;
  filename) NOTARIZATION_KEY="${scratch}/fixture.p8" ;;
  malformed) NOTARIZATION_KEY=$'-----BEGIN PRIVATE KEY-----\ninvalid-fixture\n-----END PRIVATE KEY-----' ;;
  esac
  export NOTARIZATION_KEY
  rm -f "${PACKAGE_TEST_SECURITY}"
  status=0
  bash -x "${scratch}/script/package" >"${scratch}/package.log" 2>&1 || status=$?
  if [[ "${format}" == pem || "${format}" == unwrapped || "${format}" == crlf ]]; then
    [[ "${status}" == 67 && -f "${PACKAGE_TEST_SECURITY}" ]] || exit 1
  else
    [[ "${status}" == 1 && ! -f "${PACKAGE_TEST_SECURITY}" ]] || exit 1
    grep -q 'NOTARIZATION_KEY must contain' "${scratch}/package.log"
  fi
  if grep -Fq -- "${NOTARIZATION_KEY}" "${scratch}/package.log"; then
    echo 'Packaging exposed the notarisation key' >&2
    exit 1
  fi
done
echo 'Notarisation key checks passed without accessing Keychain'
