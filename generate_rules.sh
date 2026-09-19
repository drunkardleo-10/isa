#!/usr/bin/env bash
set -euo pipefail

# Determine script and project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RULES_DIR="$PROJECT_ROOT/rules"
FINAL_OUTPUT="$RULES_DIR/content-blocker.json"
FINAL_COSMETIC_OUTPUT="$RULES_DIR/cosmetic-filters.json"
CONVERTER_MANIFEST="$PROJECT_ROOT/tools/rule-converter/Cargo.toml"

echo "=== Isa Content Blocker & Cosmetic Rule Generator ==="

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
TMP_COSMETIC_JSON="$TEMP_DIR/cosmetic-filters.json.tmp"

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

echo "[2/4] Converting network and cosmetic rules with adblock-rust..."
cargo run --release --manifest-path "$CONVERTER_MANIFEST" -- "$TMP_JSON" "$TMP_COSMETIC_JSON" "$EASYLIST_FILE" "$EASYPRIVACY_FILE"

if [ ! -s "$TMP_JSON" ]; then
  echo "Error: Rule converter produced an empty content-blocker output file. Aborting." >&2
  exit 1
fi

if [ ! -s "$TMP_COSMETIC_JSON" ]; then
  echo "Error: Rule converter produced an empty cosmetic-filters output file. Aborting." >&2
  exit 1
fi

echo "[3/4] Verifying generated rules..."
echo "  -> Verifying content blocker with WebKit WKContentRuleListStore..."
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

echo "  -> Verifying cosmetic filter JSON structure..."
swift -e '
import Foundation

let cosmeticURL = URL(fileURLWithPath: "'"$TMP_COSMETIC_JSON"'")
guard let data = try? Data(contentsOf: cosmeticURL),
      let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
    fputs("Error: cosmetic-filters.json is not valid JSON dictionary [String: String].\n", stderr)
    exit(1)
}

guard jsonObject.count > 5000 else {
    fputs("Error: cosmetic-filters.json has fewer than 5,000 domains (\(jsonObject.count)).\n", stderr)
    exit(1)
}

print("Cosmetic filters verified: \(jsonObject.count) domains loaded successfully.")
'

echo "[4/4] Finalizing compiled rules..."
mkdir -p "$RULES_DIR"
mv "$TMP_JSON" "$FINAL_OUTPUT"
mv "$TMP_COSMETIC_JSON" "$FINAL_COSMETIC_OUTPUT"

CB_SIZE=$(ls -lh "$FINAL_OUTPUT" | awk '{print $5}')
COSMETIC_SIZE=$(ls -lh "$FINAL_COSMETIC_OUTPUT" | awk '{print $5}')
echo "Success! Output written to:"
echo "  - $FINAL_OUTPUT ($CB_SIZE)"
echo "  - $FINAL_COSMETIC_OUTPUT ($COSMETIC_SIZE)"
echo "Remember to commit rules/content-blocker.json and rules/cosmetic-filters.json to the repository."
