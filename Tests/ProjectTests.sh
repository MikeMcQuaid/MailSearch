#!/bin/bash
# Exercise automatic membership without accessing Mail or credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .test-scratch .build
scratch="$(mktemp -d "${PWD}/.test-scratch/project.XXXXXX")"
directories=("${scratch}")
trap 'rm -rf "${directories[@]}"' EXIT
script/prepare
args=(-project MailSearch.xcodeproj -scheme MailSearchApp -configuration Debug
  -destination 'platform=macOS,arch=arm64' -onlyUsePackageVersionsFromResolvedFile
  -jobs 6 CODE_SIGNING_ALLOWED=NO)
if [[ -n "${SV_SESSION_ID:-}" ]]; then
  export SWIFTPM_DISABLE_SANDBOX=1 SWIFT_BUILD_USE_SANDBOX=0
  # shellcheck disable=SC2016
  args+=(-IDEPackageSupportDisableManifestSandbox=1 -IDEPackageSupportDisablePackageSandbox=1
    'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox')
fi
nice -n 10 xcodebuild "${args[@]}" -showBuildSettings -json >.build/project-xcode-settings.json 2>.build/project-xcode-settings.log
cat >"${scratch}/check-xcode-packages.py" <<'PYTHON'
import json
from pathlib import Path
import subprocess

settings = json.loads(Path(".build/project-xcode-settings.json").read_text())[0]["buildSettings"]
packages = Path(settings["BUILD_DIR"]).parents[1] / "SourcePackages"
assert json.loads(Path("Package.resolved").read_text())["pins"] == json.loads(Path("MailSearch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"]
for directory in [Path(".build"), packages]:
    for package, patch in [("swift-nio", "nio-checked-continuation.patch"), ("swift-nio-imap", "nio-imap-empty-base64.patch")]:
        checkout = directory / "checkouts" / package
        revision = next(pin["state"]["revision"] for pin in json.loads(Path("Package.resolved").read_text())["pins"] if pin["identity"] == package)
        assert subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip() == revision
        subprocess.run(["git", "-C", str(checkout), "apply", "--reverse", "--check", str(Path("script/support", patch).resolve())], check=True)
PYTHON
python3 "${scratch}/check-xcode-packages.py"
nice -n 10 xcodebuild "${args[@]}" build >.build/project-xcode.log 2>&1
python3 "${scratch}/check-xcode-packages.py"
args+=(-derivedDataPath "${scratch}/DerivedData" -clonedSourcePackagesDirPath .build)
for target in App Sources/MailSearchDomain Sources/MailSearchData Sources/MailSearchFeatures \
  Tests/MailSearchDomainTests Tests/MailSearchDataTests Tests/MailSearchFeaturesTests App/Icons; do
  directories+=("$(mktemp -d "${PWD}/${target}/MembershipProbe.XXXXXX")")
done
for directory in "${directories[@]:1:7}"; do
  printf 'struct ProjectMembershipProbe {}\n' >"${directory}/Added.swift"
done
mkdir -p "${directories[8]}/Nested/Deeper"
printf '#error("Excluded descendants must not compile")\n' >"${directories[8]}/Nested/Deeper/Excluded.swift"
printf 'Excluded resource\n' >"${directories[8]}/Nested/Deeper/Excluded.txt"
printf 'Discovered resource\n' >"${directories[1]}/Added.txt"
shasum -a 256 MailSearch.xcodeproj/project.xcproj MailSearch.xcodeproj/xcshareddata/xcschemes/*.xcscheme >"${scratch}/before"
app="${scratch}/DerivedData/Build/Products/Debug/MailSearch.app"
for state in Added Renamed Removed; do
  if [[ "${state}" == Renamed ]]; then
    for directory in "${directories[@]:1:7}"; do
      mv "${directory}/Added.swift" "${directory}/Renamed.swift"
    done
    mv "${directories[1]}/Added.txt" "${directories[1]}/Renamed.txt"
  elif [[ "${state}" == Removed ]]; then
    for directory in "${directories[@]:1:7}"; do
      rm "${directory}/Renamed.swift"
    done
    rm "${directories[1]}/Renamed.txt"
  fi
  nice -n 10 xcodebuild "${args[@]}" build >".build/project-${state}.log" 2>&1
  nice -n 10 swift build --disable-sandbox --jobs 6 --build-tests >>".build/project-${state}.log" 2>&1
  swift package --disable-sandbox describe --type json >"${scratch}/package.json"
  python3 - "${scratch}/package.json" "${state}" "${app}" <<'PYTHON'
import json
from pathlib import Path
import sys

package, state, app = sys.argv[1:]
for target in json.loads(Path(package).read_text())["targets"]:
    if target["type"] not in ("library", "test"):
        continue
    probes = [source for source in target["sources"] if "MembershipProbe." in source]
    assert len(probes) == (0 if state == "Removed" else 1), target["name"]
    assert all(source.endswith(f"/{state}.swift") for source in probes), target["name"]
resources = Path(app) / "Contents/Resources"
assert not (resources / "Info.plist").exists()
assert not any(path.name in ("Excluded.swift", "Excluded.txt", "MailSearch.entitlements", "GENERATION.md", "Icons") for path in resources.rglob("*"))
if state != "Removed":
    assert (resources / f"{state}.txt").read_text() == "Discovered resource\n"
assert (resources / "AppIcon.icns").is_file()
assert (resources / "Assets.car").is_file()
assert (resources / "LICENSE").is_file()
assert (resources / "THIRD-PARTY-NOTICES.txt").is_file()
assert (resources / "swift-nio_NIOPosix.bundle/Contents/Resources/PrivacyInfo.xcprivacy").is_file()
PYTHON
  if [[ "${state}" != Removed ]]; then
    grep -Fq "/${state}.swift" "${scratch}/DerivedData/Build/Intermediates.noindex/MailSearch.build/Debug/MailSearchApp.build/Objects-normal/arm64/MailSearch.SwiftFileList"
  elif grep -Fq 'MembershipProbe.' "${scratch}/DerivedData/Build/Intermediates.noindex/MailSearch.build/Debug/MailSearchApp.build/Objects-normal/arm64/MailSearch.SwiftFileList"; then
    echo 'Removed sources remain in the app build' >&2
    exit 1
  fi
  shasum -a 256 MailSearch.xcodeproj/project.xcproj MailSearch.xcodeproj/xcshareddata/xcschemes/*.xcscheme >"${scratch}/after"
  cmp "${scratch}/before" "${scratch}/after"
done
echo 'Project source, resource, exclusion and isolation checks passed'
