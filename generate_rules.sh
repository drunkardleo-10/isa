#!/usr/bin/env bash
set -euo pipefail

# Determine script and project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RULES_DIR="$PROJECT_ROOT/rules"
FINAL_OUTPUT="$RULES_DIR/content-blocker.json"
FINAL_COSMETIC_OUTPUT="$RULES_DIR/cosmetic-filters.json"
FINAL_SCRIPTLETS_OUTPUT="$RULES_DIR/scriptlets.json"
CONVERTER_MANIFEST="$PROJECT_ROOT/tools/rule-converter/Cargo.toml"
BASELINE_RESOURCES="$PROJECT_ROOT/tools/rule-converter/resources.json"

echo "=== Isa Content Blocker, Cosmetic & Scriptlet Rule Generator ==="

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
UBLOCK_FILTERS_URL="https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
UBLOCK_QUICK_FIXES_URL="https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt"
RESOURCES_URL="https://raw.githubusercontent.com/brave/adblock-rust/master/data/brave/brave-resources.json"

EASYLIST_FILE="$TEMP_DIR/easylist.txt"
EASYPRIVACY_FILE="$TEMP_DIR/easyprivacy.txt"
UBLOCK_FILTERS_FILE="$TEMP_DIR/filters.txt"
UBLOCK_QUICK_FIXES_FILE="$TEMP_DIR/quick-fixes.txt"
RESOURCES_FILE="$TEMP_DIR/resources.json"

TMP_JSON="$TEMP_DIR/content-blocker.json.tmp"
TMP_COSMETIC_JSON="$TEMP_DIR/cosmetic-filters.json.tmp"
TMP_SCRIPTLETS_JSON="$TEMP_DIR/scriptlets.json.tmp"

echo "[1/4] Fetching filter lists and scriptlet resources..."
echo "  -> Fetching EasyList from $EASYLIST_URL"
curl --connect-timeout 15 -fsSL "$EASYLIST_URL" -o "$EASYLIST_FILE" || {
  echo "Error: Failed to download EasyList from $EASYLIST_URL" >&2
  exit 1
}

echo "  -> Fetching EasyPrivacy from $EASYPRIVACY_URL"
curl --connect-timeout 15 -fsSL "$EASYPRIVACY_URL" -o "$EASYPRIVACY_FILE" || {
  echo "Error: Failed to download EasyPrivacy from $EASYPRIVACY_URL" >&2
  exit 1
}

echo "  -> Fetching uBlock filters from $UBLOCK_FILTERS_URL"
curl --connect-timeout 15 -fsSL "$UBLOCK_FILTERS_URL" -o "$UBLOCK_FILTERS_FILE" || {
  echo "Error: Failed to download uBlock filters from $UBLOCK_FILTERS_URL" >&2
  exit 1
}

echo "  -> Fetching uBlock quick-fixes from $UBLOCK_QUICK_FIXES_URL"
curl --connect-timeout 15 -fsSL "$UBLOCK_QUICK_FIXES_URL" -o "$UBLOCK_QUICK_FIXES_FILE" || {
  echo "Error: Failed to download uBlock quick-fixes from $UBLOCK_QUICK_FIXES_URL" >&2
  exit 1
}

echo "  -> Fetching adblock-rust scriptlet resources from $RESOURCES_URL"
if curl --connect-timeout 15 -fsSL "$RESOURCES_URL" -o "$RESOURCES_FILE"; then
  echo "  -> Successfully fetched live brave-resources.json"
  cp "$RESOURCES_FILE" "$BASELINE_RESOURCES" || true
elif [ -f "$BASELINE_RESOURCES" ]; then
  echo "  -> Warning: Live resources download failed, using baseline $BASELINE_RESOURCES"
  cp "$BASELINE_RESOURCES" "$RESOURCES_FILE"
else
  echo "Error: Failed to download resources and no baseline found." >&2
  exit 1
fi

# Validate downloaded lists are non-empty and complete
EASYLIST_LINES=$(wc -l < "$EASYLIST_FILE" | tr -d ' ')
EASYPRIVACY_LINES=$(wc -l < "$EASYPRIVACY_FILE" | tr -d ' ')
UBLOCK_LINES=$(wc -l < "$UBLOCK_FILTERS_FILE" | tr -d ' ')
QUICK_FIXES_LINES=$(wc -l < "$UBLOCK_QUICK_FIXES_FILE" | tr -d ' ')

echo "  -> Downloaded EasyList: $EASYLIST_LINES lines"
echo "  -> Downloaded EasyPrivacy: $EASYPRIVACY_LINES lines"
echo "  -> Downloaded uBlock Filters: $UBLOCK_LINES lines"
echo "  -> Downloaded uBlock Quick Fixes: $QUICK_FIXES_LINES lines"

if [ "$EASYLIST_LINES" -lt 30000 ]; then
  echo "Error: EasyList appears truncated or corrupt (fewer than 30,000 lines). Aborting." >&2
  exit 1
fi

if [ "$EASYPRIVACY_LINES" -lt 20000 ]; then
  echo "Error: EasyPrivacy appears truncated or corrupt (fewer than 20,000 lines). Aborting." >&2
  exit 1
fi

if [ "$UBLOCK_LINES" -lt 1000 ]; then
  echo "Error: uBlock filters list appears truncated (fewer than 1,000 lines). Aborting." >&2
  exit 1
fi

echo "[2/4] Converting network, cosmetic, and scriptlet rules with adblock-rust..."
cargo run --release --manifest-path "$CONVERTER_MANIFEST" -- \
  "$TMP_JSON" \
  "$TMP_COSMETIC_JSON" \
  "$TMP_SCRIPTLETS_JSON" \
  "$RESOURCES_FILE" \
  "$EASYLIST_FILE" \
  "$EASYPRIVACY_FILE" \
  "$UBLOCK_FILTERS_FILE" \
  "$UBLOCK_QUICK_FIXES_FILE"

if [ ! -s "$TMP_JSON" ]; then
  echo "Error: Rule converter produced an empty content-blocker output file. Aborting." >&2
  exit 1
fi

if [ ! -s "$TMP_COSMETIC_JSON" ]; then
  echo "Error: Rule converter produced an empty cosmetic-filters output file. Aborting." >&2
  exit 1
fi

if [ ! -s "$TMP_SCRIPTLETS_JSON" ]; then
  echo "Error: Rule converter produced an empty scriptlets output file. Aborting." >&2
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

echo "  -> Verifying scriptlets JSON structure and YouTube entries..."
swift -e '
import Foundation

let scriptletsURL = URL(fileURLWithPath: "'"$TMP_SCRIPTLETS_JSON"'")
guard let data = try? Data(contentsOf: scriptletsURL),
      let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
    fputs("Error: scriptlets.json is not a valid JSON dictionary [String: [String]].\n", stderr)
    exit(1)
}

guard let ytScriptlets = jsonObject["youtube.com"], !ytScriptlets.isEmpty else {
    fputs("FATAL: scriptlets.json does NOT contain a non-empty entry for \"youtube.com\". Aborting!\n", stderr)
    exit(1)
}

for (idx, snippet) in ytScriptlets.enumerated() {
    let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty && trimmed.count > 100 else {
        fputs("FATAL: YouTube scriptlet at index \(idx) appears empty or placeholder (\(trimmed.count) chars).\n", stderr)
        exit(1)
    }
}

print("Scriptlets verified: contains \(jsonObject.count) domains; youtube.com has \(ytScriptlets.count) fully resolved snippets.")
'

echo "[4/4] Finalizing compiled rules..."
mkdir -p "$RULES_DIR"
mv "$TMP_JSON" "$FINAL_OUTPUT"
mv "$TMP_COSMETIC_JSON" "$FINAL_COSMETIC_OUTPUT"
mv "$TMP_SCRIPTLETS_JSON" "$FINAL_SCRIPTLETS_OUTPUT"

CB_SIZE=$(ls -lh "$FINAL_OUTPUT" | awk '{print $5}')
COSMETIC_SIZE=$(ls -lh "$FINAL_COSMETIC_OUTPUT" | awk '{print $5}')
SCRIPTLETS_SIZE=$(ls -lh "$FINAL_SCRIPTLETS_OUTPUT" | awk '{print $5}')

echo "Success! Output written to:"
echo "  - $FINAL_OUTPUT ($CB_SIZE)"
echo "  - $FINAL_COSMETIC_OUTPUT ($COSMETIC_SIZE)"
echo "  - $FINAL_SCRIPTLETS_OUTPUT ($SCRIPTLETS_SIZE)"
echo "Remember to commit rules/ files to the repository."
