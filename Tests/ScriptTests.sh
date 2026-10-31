#!/bin/bash
# Check development scripts without accessing Mail or credentials.
set -euo pipefail

cd "$(dirname "$0")/.."
python3 - <<'PYTHON'
import hashlib
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET

project = Path("MailSearch.xcodeproj")
assert (project / "project.xcproj").is_file(), "Native JSON project is missing"
assert not (project / "project.pbxproj").exists(), "Legacy project must not remain"
for reference in ET.parse(project / "xcshareddata/xcschemes/MailSearchApp.xcscheme").iter("BuildableReference"):
    assert reference.get("BuildableName") == "MailSearch.app", "Scheme product must match the output bundle"
for workflow in [Path(".github/workflows/tests.yml"), Path(".github/workflows/release.yml")]:
    for step in workflow.read_text().split("      - name:"):
        if "uses: actions/cache@" not in step or "/checkouts" not in step:
            continue
        patterns = re.findall(r"'([^']+)'", re.search(r"key: (.+)", step)[1])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inputs = {path for pattern in patterns for path in Path().glob(pattern) if path.is_file()}
            inputs.update([Path("script/prepare"), *Path("script/support").glob("*.patch")])
            for path in inputs:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_bytes(path.read_bytes())
            def cache_hash():
                return hashlib.sha256(b"".join(path.read_bytes() for path in sorted({path for pattern in patterns for path in root.glob(pattern) if path.is_file()}))).digest()
            original = cache_hash()
            for path in [Path("script/prepare"), *Path("script/support").glob("*.patch")]:
                (root / path).write_bytes(path.read_bytes() + b"\n")
                assert cache_hash() != original, f"{workflow}: changing {path} must invalidate the cache"
                (root / path).write_bytes(path.read_bytes())
            (root / "script/support/new-dependency.patch").write_text("Fixture patch\n")
            assert cache_hash() != original, f"{workflow}: new patches must invalidate the cache"
        assert "restore-keys:" not in step, f"{workflow}: patched checkouts require exact cache restores"
PYTHON
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

cp script/bootstrap script/build script/style "${scratch}/script/"
mkdir -p "${scratch}/bin" "${scratch}/MailSearch.xcodeproj" \
  "${scratch}/.DerivedData/Build/Products/Release/MailSearch.app"
touch "${scratch}/Package.resolved"
for command in brew python3 codesign swiftformat swiftlint shellcheck shfmt actionlint zizmor; do
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
for marker in - '*' +; do
  for count in 4 5 6; do
    {
      printf '# Fixture\n\n- Outside Features\n\n## ✨ Features\n\n'
      for ((bullet = 1; bullet <= count; bullet++)); do
        printf '%s Feature %s\n  Wrapped description.\n' "${marker}" "${bullet}"
      done
      printf '\n## Other\n\n- Outside Features\n'
    } >"${scratch}/README.md"
    status=0
    "${scratch}/script/style" >"${scratch}/style.log" 2>&1 || status=$?
    if [[ "${count}" -le 5 ]]; then
      [[ "${status}" == 0 ]] || {
        cat "${scratch}/style.log"
        exit 1
      }
    else
      [[ "${status}" != 0 ]] || {
        echo 'Style accepted six README features' >&2
        exit 1
      }
      grep -q 'README.md: Features has 6 bullets; keep at most 5' "${scratch}/style.log"
    fi
  done
done
for count in 99 100 101; do
  {
    printf '## ✨ Features\n- Feature\n## Other\n'
    for ((line = 3; line < count; line++)); do
      printf 'Paragraph.\n'
    done
  } >"${scratch}/README.md"
  status=0
  "${scratch}/script/style" >"${scratch}/style.log" 2>&1 || status=$?
  if [[ "${count}" -le 100 ]]; then
    [[ "${status}" == 0 ]] || {
      cat "${scratch}/style.log"
      exit 1
    }
  else
    [[ "${status}" != 0 ]] || {
      echo 'Style accepted 101 README lines' >&2
      exit 1
    }
    grep -q 'README.md: keep at most 100 lines when wrapped at 80 columns' "${scratch}/style.log"
  fi
done
{
  printf '## ✨ Features\n- Feature\n## Other\n'
  for ((word = 0; word < 1000; word++)); do
    printf 'Paragraph. '
  done
  printf '\n'
} >"${scratch}/README.md"
if "${scratch}/script/style" >"${scratch}/style.log" 2>&1; then
  echo 'Style accepted a README exceeding the wrapped line limit' >&2
  exit 1
fi
grep -q 'README.md: keep at most 100 lines when wrapped at 80 columns' "${scratch}/style.log"
printf '# No Features section\n' >"${scratch}/README.md"
if "${scratch}/script/style" >"${scratch}/style.log" 2>&1; then
  echo 'Style accepted a missing README Features section' >&2
  exit 1
fi
grep -q 'README.md: missing Features section' "${scratch}/style.log"
echo 'README style tests passed'

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

cp script/install "${scratch}/script/install"
mkdir -p "${scratch}/install-bin"
cat >"${scratch}/install-bin/command" <<'COMMAND'
#!/bin/bash
set -euo pipefail
command="$(basename "$0")"
printf '%s\n' "${command}${*:+ }$*" >>"${INSTALL_TEST_LOG}"
[[ "${command}" != "${INSTALL_TEST_FAILURE}" ]]
COMMAND
for command in osascript rm ditto open; do
  cp "${scratch}/install-bin/command" "${scratch}/install-bin/${command}"
done
cp "${scratch}/install-bin/command" "${scratch}/script/build"
chmod +x "${scratch}/install-bin/"* "${scratch}/script/build"
export INSTALL_TEST_LOG="${scratch}/install.log"
cat >"${scratch}/install-expected.log" <<'EXPECTED'
build
osascript -e quit app "MailSearch"
rm -rf /Applications/MailSearch.app
ditto MailSearch.app /Applications/MailSearch.app
open /Applications/MailSearch.app
EXPECTED
for INSTALL_TEST_FAILURE in none osascript build ditto; do
  export INSTALL_TEST_FAILURE
  : >"${INSTALL_TEST_LOG}"
  status=0
  PATH="${scratch}/install-bin:${PATH}" "${scratch}/script/install" &>/dev/null || status=$?
  case "${INSTALL_TEST_FAILURE}" in
  none | osascript)
    [[ "${status}" == 0 ]] || exit 1
    diff -u "${scratch}/install-expected.log" "${INSTALL_TEST_LOG}"
    ;;
  build | ditto)
    [[ "${status}" != 0 ]] || exit 1
    if [[ "${INSTALL_TEST_FAILURE}" == build ]]; then
      head -1 "${scratch}/install-expected.log" >"${scratch}/install-failure.log"
    else
      head -4 "${scratch}/install-expected.log" >"${scratch}/install-failure.log"
    fi
    diff -u "${scratch}/install-failure.log" "${INSTALL_TEST_LOG}"
    ;;
  esac
done
echo 'Install script tests passed without changing installed or running apps'

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
