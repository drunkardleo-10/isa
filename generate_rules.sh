#!/usr/bin/env bash
set -euo pipefail

# Determine script and project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RULES_DIR="$PROJECT_ROOT/rules"
FINAL_OUTPUT="$RULES_DIR/content-blocker.json"
CONVERTER_MANIFEST="$PROJECT_ROOT/tools/rule-converter/Cargo.toml"

echo "=== Isa Content Blocker Rule Generator ==="

# Check prerequisites
for cmd in curl cargo swift; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required tool '$cmd' is not installed or not in PATH." >&2
    exit 1
  fi
done

# Create temporary workspace for downloads and intermediate output
TEMP_DIR="$(mktemp -d -t isa-rules-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

EASYLIST_URL="https://easylist.to/easylist/easylist.txt"
EASYPRIVACY_URL="https://easylist.to/easylist/easyprivacy.txt"

EASYLIST_FILE="$TEMP_DIR/easylist.txt"
EASYPRIVACY_FILE="$TEMP_DIR/easyprivacy.txt"
TMP_JSON="$TEMP_DIR/content-blocker.json.tmp"

echo "[1/4] Fetching filter lists..."
echo "  -> Fetching EasyList from $EASYLIST_URL"
curl -fsSL --retry 3 --retry-connrefused "$EASYLIST_URL" -o "$EASYLIST_FILE" || {
  echo "Error: Failed to download EasyList from $EASYLIST_URL" >&2
  exit 1
}

echo "  -> Fetching EasyPrivacy from $EASYPRIVACY_URL"
curl -fsSL --retry 3 --retry-connrefused "$EASYPRIVACY_URL" -o "$EASYPRIVACY_FILE" || {
  echo "Error: Failed to download EasyPrivacy from $EASYPRIVACY_URL" >&2
  exit 1
}

# Validate downloaded lists are non-empty and complete
EASYLIST_LINES=$(wc -l < "$EASYLIST_FILE" | tr -d ' ')
EASYPRIVACY_LINES=$(wc -l < "$EASYPRIVACY_FILE" | tr -d ' ')

echo "  -> Downloaded EasyList: $EASYLIST_LINES lines"
echo "  -> Downloaded EasyPrivacy: $EASYPRIVACY_LINES lines"

if [ "$EASYLIST_LINES" -lt 30000 ]; then
  echo "Error: EasyList appears truncated or corrupt (fewer than 30,000 lines). Aborting." >&2
  exit 1
fi

if [ "$EASYPRIVACY_LINES" -lt 20000 ]; then
  echo "Error: EasyPrivacy appears truncated or corrupt (fewer than 20,000 lines). Aborting." >&2
  exit 1
fi

echo "[2/4] Converting rules with adblock-rust..."
cargo run --release --manifest-path "$CONVERTER_MANIFEST" -- "$TMP_JSON" "$EASYLIST_FILE" "$EASYPRIVACY_FILE"

if [ ! -s "$TMP_JSON" ]; then
  echo "Error: Rule converter produced an empty output file. Aborting." >&2
  exit 1
fi

echo "[3/4] Verifying generated rules with WebKit WKContentRuleListStore..."
swift -e '
import WebKit
import Foundation

let jsonURL = URL(fileURLWithPath: "'"$TMP_JSON"'")
guard let data = try? Data(contentsOf: jsonURL),
      let json = String(data: data, encoding: .utf8) else {
    fputs("Error: Unable to read intermediate JSON file.\n", stderr)
    exit(1)
}

let testIdentifier = "isa.verify." + UUID().uuidString
var compileSuccess = false

WKContentRuleListStore.default().compileContentRuleList(forIdentifier: testIdentifier, encodedContentRuleList: json) { list, error in
    if let error = error {
        fputs("WebKit compile verification failed: \(error.localizedDescription)\n", stderr)
        CFRunLoopStop(CFRunLoopGetMain())
        return
    }
    compileSuccess = true
    WKContentRuleListStore.default().removeContentRuleList(forIdentifier: testIdentifier) { _ in
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
CFRunLoopRun()
exit(compileSuccess ? 0 : 1)
'

echo "[4/4] Finalizing compiled rules..."
mkdir -p "$RULES_DIR"
mv "$TMP_JSON" "$FINAL_OUTPUT"

FILE_SIZE=$(ls -lh "$FINAL_OUTPUT" | awk '{print $5}')
echo "Success! Output written to $FINAL_OUTPUT ($FILE_SIZE)"
echo "Remember to commit rules/content-blocker.json to the repository."
