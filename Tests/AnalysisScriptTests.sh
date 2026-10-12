#!/bin/bash
# Analysis must reject stale builds and run both independent passes.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .test-scratch
scratch="$(mktemp -d "${PWD}/.test-scratch/analysis.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
mkdir -p "${scratch}/bin" "${scratch}/script" "${scratch}/.build/analyze"
mkdir -p "${scratch}/Sources" "${scratch}/App" "${scratch}/Tests"
touch "${scratch}/App/MailSearchApp.swift"
cp script/analyze "${scratch}/script/"
printf '#!/bin/bash\nexit 0\n' >"${scratch}/script/prepare"
printf '#!/bin/bash\nexit 0\n' >"${scratch}/bin/python3"
printf '#!/bin/bash\necho /toolchain/usr/bin/swiftc\n' >"${scratch}/bin/xcrun"
cat >"${scratch}/bin/swift" <<'SWIFT'
#!/bin/bash
if [[ "$*" == *--show-bin-path* ]]; then
  echo "$PWD/.build/analyze/debug"
elif [[ "$*" == *describe* ]]; then
  echo '{}'
else
  [[ ! -f .build/analyze/stale ]] || exit 98
  [[ "$*" == *'-Xswiftc -load-resolved-plugin -Xswiftc /toolchain/usr/bin/../lib/swift/host/plugins/testing/libTestingMacros.dylib#/toolchain/usr/bin/swift-plugin-server#TestingMacros'* ]] || exit 97
  if [[ -n "${SV_SESSION_ID:-}" ]]; then
    [[ "$*" == *'-Xswiftc -Xfrontend -Xswiftc -disable-sandbox'* ]] || exit 96
  fi
  echo 'swiftc -module-name MailSearchAppSources App/MailSearchApp.swift'
  exit "${ANALYSIS_BUILD_STATUS}"
fi
SWIFT
for command in swiftlint periphery; do
  cat >"${scratch}/bin/${command}" <<'ANALYSER'
#!/bin/bash
command="$(basename "$0")"
echo "$command" >>"${ANALYSIS_CALLS}"
if [[ "$command" == swiftlint ]]; then
  echo "${ANALYSIS_LINT_OUTPUT:-}"
  exit "${ANALYSIS_LINT_STATUS}"
fi
exit "${ANALYSIS_PERIPHERY_STATUS}"
ANALYSER
done
chmod +x "${scratch}/bin/"* "${scratch}/script/"*
export PATH="${scratch}/bin:${PATH}"
export ANALYSIS_CALLS="${scratch}/calls"
for session in host sandbox; do
  if [[ "$session" == sandbox ]]; then export SV_SESSION_ID=fixture; else unset SV_SESSION_ID; fi
  for scenario in clean build lint periphery unavailable incomplete; do
    export ANALYSIS_BUILD_STATUS=0 ANALYSIS_LINT_STATUS=0 ANALYSIS_PERIPHERY_STATUS=0 ANALYSIS_LINT_OUTPUT='Done analyzing! Found 0 violations, 0 serious in 1 files.'
    case "$scenario" in
    build) ANALYSIS_BUILD_STATUS=65 ;;
    lint) ANALYSIS_LINT_STATUS=2 ;;
    periphery) ANALYSIS_PERIPHERY_STATUS=3 ;;
    unavailable) ANALYSIS_LINT_OUTPUT='Skipping App/MailSearchApp.swift: no compiler arguments' ;;
    incomplete) ANALYSIS_LINT_OUTPUT='' ;;
    esac
    mkdir -p "${scratch}/.build/analyze"
    touch "${scratch}/.build/analyze/stale"
    : >"${ANALYSIS_CALLS}"
    status=0
    "${scratch}/script/analyze" >"${scratch}/output" 2>&1 || status=$?
    if [[ "$scenario" == clean ]]; then
      [[ "$status" == 0 ]] || {
        cat "${scratch}/output"
        exit 1
      }
    else
      [[ "$status" != 0 ]] || {
        echo "Analysis accepted ${scenario} (${session})" >&2
        exit 1
      }
    fi
    if [[ "$scenario" == build ]]; then
      [[ ! -s "$ANALYSIS_CALLS" ]] || exit 1
    else
      [[ "$(cat "$ANALYSIS_CALLS")" == $'swiftlint\nperiphery' ]] || {
        echo "Both analysis passes must run (${scenario}, ${session})" >&2
        exit 1
      }
    fi
  done
done
echo 'Analysis script tests passed'

# Every scratch checkout must receive the pinned dependency fixes.
cp script/prepare "${scratch}/script/prepare"
cat >"${scratch}/bin/swift" <<'SWIFT'
#!/bin/bash
[[ "$*" == "package --disable-sandbox --scratch-path ${PREPARE_TEST_SCRATCH} --force-resolved-versions resolve" ]]
SWIFT
cat >"${scratch}/bin/git" <<'GIT'
#!/bin/bash
[[ "$1" == -C && "$2" == "${PREPARE_TEST_SCRATCH}/checkouts/"* ]] || exit 99
if [[ "$3" == rev-parse ]]; then
  case "$2" in
    */swift-nio) echo 21de5f08c1a166a6dd293d0e587ad977bf8dac5d ;;
    */swift-nio-imap) echo d67f1243f731457cb9f2eb0beb27eff9e533bf7b ;;
    *) exit 98 ;;
  esac
elif [[ "$*" == *--reverse* ]]; then
  exit 1
else
  echo "$2" >>"${ANALYSIS_CALLS}"
fi
GIT
chmod +x "${scratch}/bin/git"
for PREPARE_TEST_SCRATCH in .build .build/address-sanitizer .build/thread-sanitizer .build/analyze; do
  export PREPARE_TEST_SCRATCH
  : >"${ANALYSIS_CALLS}"
  "${scratch}/script/prepare" "$PREPARE_TEST_SCRATCH"
  [[ "$(wc -l <"${ANALYSIS_CALLS}" | tr -d ' ')" == 2 ]]
done
echo 'Dependency patches follow the selected scratch directory'
