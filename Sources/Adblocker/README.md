# Adblocker Module

Native WebKit content-blocking integration for `isa`, powered by compiled network filtering rules from EasyList and EasyPrivacy.

---

## What This Base Version Does and Does Not Do

### What it does:
- **Network Request Blocking**: Blocks network requests matching EasyList and EasyPrivacy network rules (advertisements, analytics, trackers, fingerprinting scripts, and known ad-serving domains).
- **Subresource Coverage**: Operates natively within WebKit's `WKContentRuleList` engine, blocking matching subresources (scripts, images, iframes, stylesheets, and XHR/fetch calls) before network transmission occurs, not just top-level navigations.
- **One-Time Persistent Compilation**: Automatically checks `WKContentRuleListStore.default().lookUpContentRuleList` to reuse WebKit's on-disk compiled bytecode across app launches. Rule compilation happens only on the first cold launch or after rule updates, avoiding repeated overhead.
- **Thread-Safe & Zero-Regression Multi-Tab Cold Launch**: Ensures that rapid tab openings immediately at launch cannot bypass the blocker; WebViews are never initialized without rules attached.

### What it does NOT do:
- **No Cosmetic Filtering**: Does not perform cosmetic element hiding (CSS `#container { display: none }` rules to hide empty ad placeholders or collapsed frames). Cosmetic filtering is planned as a separate experiment.
- **No Scriptlets / Script Injection**: Does not inject scriptlet de-fang routines or custom anti-adblock defusers.
- **No Dynamic / Live Rule Updates**: Rules are not fetched or updated over the air at runtime.
- **No Per-Site Allowlisting or UI**: There is currently no UI toggle or per-domain exception whitelist in this pass.
- **Static Snapshot**: Rules are a point-in-time snapshot generated when `generate_rules.sh` was last run.

---

## Tooling & Architecture: Why `adblock-rust` CLI Was Chosen

During evaluation between the Rust CLI vs the published npm/WASM build (`adblock-rs`):
1. **API Capability**: The npm package `adblock-rs` only exposes the runtime matching engine (`Engine`) for Node.js. It does **not** expose the Apple Safari/WebKit `content-blocking` conversion module.
2. **Setup Cost**: The npm package actually compiles native Rust code via `cargo build` during its `postinstall` hook anyway, so an active Rust toolchain is required in both cases.
3. **Native Support**: The native `adblock` Rust crate (`v0.13.3`) includes built-in, first-class support for `features = ["content-blocking"]`. It provides exact `WKContentRuleList`-compatible rule definitions (`CbRule`, `CbTrigger`, `CbAction`, and `ignore_previous_fp_documents`), parsing ~140,000 raw rules and outputting verified Safari JSON in ~80 milliseconds.

Consequently, `tools/rule-converter/` was built as a dedicated Rust CLI using the `adblock` crate.

---

## Developer Workflow: Updating Rules

`generate_rules.sh` is a **developer-time tool**, not something the app runs at runtime (similar to how `xcodegen` is a developer-only tool for this project).

To update the rules to the latest EasyList and EasyPrivacy snapshots:

```bash
./generate_rules.sh
```

### What `generate_rules.sh` does:
1. Downloads the latest `easylist.txt` and `easyprivacy.txt` using `curl` with retries into a secure temporary directory.
2. Validates line counts to ensure downloads are complete and uncorrupted.
3. Runs `scripts/rule-converter` to transform ABP network syntax into WebKit content-blocking JSON.
4. Validates the output with WebKit's native `WKContentRuleListStore.compileContentRuleList` to guarantee that WebKit accepts the rules.
5. Atomically writes the result to `rules/content-blocker.json`.
6. Cleans up all temporary raw list files.

After running `generate_rules.sh`, commit the updated `rules/content-blocker.json` to git.
