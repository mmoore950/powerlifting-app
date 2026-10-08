#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
output="$PWD/artifacts/native-ci"
mkdir -p "$output"
phase="${1:?Expected setup/core/http-setup/http-contract/prepare/build/test/screenshots/summary}"
if [[ "$phase" != summary ]]; then
  # pipefail propagates command failures; logs survive ordinary step failures.
  exec > >(tee "$output/$phase.log") 2>&1
  trap 'status=$?; printf "%s\n" "$status" > "$output/'"$phase"'.exit-code"' EXIT
  printf 'Phase: %s\nUTC: %s\nRevision: %s\n' "$phase" "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)"
fi
case "$phase" in
  setup)
    sw_vers
    uname -m
    xcode-select -p
    xcodebuild -version
    swift --version
    xcrun --sdk iphonesimulator --show-sdk-version
    python3 --version
    tool_dir="${RUNNER_TEMP:?Hosted runner temp directory required}/powerlifting-xcodegen"
    mkdir -p "$tool_dir"
    curl --fail --location --max-time 120 --retry 2 \
      https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
      --output "$tool_dir/xcodegen.zip"
    printf '%s  %s\n' \
      4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 \
      "$tool_dir/xcodegen.zip" | shasum -a 256 --check
    unzip -q "$tool_dir/xcodegen.zip" -d "$tool_dir"
    tool="$tool_dir/xcodegen/bin/xcodegen"
    test -f "$tool"
    chmod +x "$tool"
    "$tool" --version
    "$tool" --version | grep -Eq '(^|[^0-9])2\.46\.0([^0-9]|$)'
    printf '%s\n' "$(dirname "$tool")" >> "${GITHUB_PATH:?}"
    ;;
  core)
    swift test --package-path Packages/LiftingCore
    ;;
  http-setup)
    # Both archives are pinned and checked before execution. No setup action or script hook.
    tool_dir="${RUNNER_TEMP:?}/powerlifting-http-tools"
    mkdir -p "$tool_dir/node" "$tool_dir/pnpm"
    curl --fail --location --max-time 60 --retry 1 \
      https://nodejs.org/dist/v24.19.0/node-v24.19.0-darwin-x64.tar.gz \
      --output "$tool_dir/node.tar.gz"
    printf '%s  %s\n' d1b5e999db158c62fe8f7267a4476b035d8bd93b1a605bac24a3f0dd166e3316 \
      "$tool_dir/node.tar.gz" | shasum -a 256 --check
    tar -xzf "$tool_dir/node.tar.gz" --strip-components=1 -C "$tool_dir/node"
    export PATH="$tool_dir/node/bin:$PATH"
    test "$(node --version)" = v24.19.0
    curl --fail --location --max-time 60 --retry 1 \
      https://registry.npmjs.org/pnpm/-/pnpm-11.25.0.tgz --output "$tool_dir/pnpm.tgz"
    python3 - "$tool_dir/pnpm.tgz" <<'PY'
import base64, hashlib, sys
expected = 'XN6SW08HX3Jetx+64YpC/+eEUkeJ8ZthxzHLhyHsKKruFg4BqNWvT+2ypCzb8wDv4j2zVrDUoXtNY+EfirfJVg=='
with open(sys.argv[1], 'rb') as stream:
    actual = base64.b64encode(hashlib.sha512(stream.read()).digest()).decode()
if actual != expected:
    raise SystemExit('Pinned pnpm archive integrity mismatch')
print('Verified pinned pnpm 11.25.0 archive SHA-512')
PY
    tar -xzf "$tool_dir/pnpm.tgz" --strip-components=1 -C "$tool_dir/pnpm"
    test "$(node "$tool_dir/pnpm/bin/pnpm.cjs" --version)" = 11.25.0
    node "$tool_dir/pnpm/bin/pnpm.cjs" --dir DataService install --frozen-lockfile --ignore-scripts --prod
    printf '%s\n' "$tool_dir/node/bin" >> "${GITHUB_PATH:?}"
    ;;
  http-contract)
    test "$(node --version)" = v24.19.0
    node tools/ci/native-http-contract.mjs
    ;;
  prepare)
    xcodegen --version
    xcodegen generate --spec project.yml
    xcodebuild -list -project PowerliftingApp.xcodeproj
    xcrun simctl list --json > "$output/simulators.json"
    python3 tools/ci/select-simulator.py "$output/simulators.json" > "$output/selected-simulator.json"
    cat "$output/selected-simulator.json"
    python3 - "$output/selected-simulator.json" "${GITHUB_OUTPUT:?}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    selected = json.load(stream)
with open(sys.argv[2], "a", encoding="utf-8") as stream:
    stream.write(f"simulator_id={selected['udid']}\n")
PY
    ;;
  build|test)
    : "${SIMULATOR_ID:?Simulator selection missing}"
    # A single destination; no signing credentials, accounts or device provisioning.
    xcodebuild -project PowerliftingApp.xcodeproj -scheme PowerliftingApp \
      -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
      -destination-timeout 60 \
      -derivedDataPath "$RUNNER_TEMP/powerlifting-derived-data" \
      -resultBundlePath "$output/$phase.xcresult" \
      -parallel-testing-enabled NO \
      -maximum-concurrent-test-simulator-destinations 1 \
      CODE_SIGNING_ALLOWED=NO "$phase"
    ;;
  screenshots)
    # Keep successful UI-test attachments as ordinary files for visual review.
    # This runs only after test success; failed runs still preserve test.xcresult.
    xcrun xcresulttool export attachments --path "$output/test.xcresult" \
      --output-path "$output/screenshots"
    python3 - "$output/screenshots" <<'PY'
from pathlib import Path
import sys
screenshots = list(Path(sys.argv[1]).rglob("*.png"))
print(f"Exported PNG attachments: {len(screenshots)}")
if len(screenshots) < 5:
    raise SystemExit("Expected at least five UI smoke screenshot attachments")
PY
    ;;
  summary)
    {
      printf '## Native validation diagnostics\n\n'
      printf 'Runner label: `macos-15-intel`; actual versions are in setup.log.\n\n'
      printf 'Revision: `%s`\n\n' "$(git rev-parse HEAD)"
      for checked_phase in setup core http-setup http-contract prepare build test screenshots; do
        if [[ -f "$output/$checked_phase.exit-code" ]]; then
          printf -- '- %s exit code: %s\n' "$checked_phase" "$(cat "$output/$checked_phase.exit-code")"
        else
          printf -- '- %s: no completed phase evidence\n' "$checked_phase"
        fi
      done
      printf '\nSimulator build/tests do not establish device UI, video accuracy, signing or release readiness.\n'
    } | tee "$output/summary.md" >> "${GITHUB_STEP_SUMMARY:?}"
    ;;
  *) printf 'Unknown phase: %s\n' "$phase" >&2; exit 2 ;;
esac
