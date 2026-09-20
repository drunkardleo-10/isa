# Adblocker Module

Native WebKit content-blocking, cosmetic element hiding, and scriptlet injection integration for `isa`, powered by compiled network filtering rules, cosmetic CSS selectors from EasyList / EasyPrivacy, and uBlock Origin-compatible scriptlets resolved via `adblock-rust`.

---

## What This Version Does and Does Not Do

### What it does:
- **Network Request Blocking**: Blocks network requests matching EasyList and EasyPrivacy network rules (advertisements, analytics, trackers, fingerprinting scripts, and known ad-serving domains).
- **Subresource Coverage**: Operates natively within WebKit's `WKContentRuleList` engine, blocking matching subresources (scripts, images, iframes, stylesheets, and XHR/fetch calls) before network transmission occurs, not just top-level navigations.
- **Cosmetic Element Hiding**: Injects domain-targeted CSS selectors as a `WKUserScript` at `.atDocumentStart`, collapsing empty ad slots, sponsor placeholders, and leftover gray boxes before the DOM paints to eliminate layout flicker (FOUC).
- **In-Stream Video Ad Defusal (Scriptlet Pipeline)**: Defuses YouTube in-stream video ads (prerolls, midrolls, and ad break placements) by injecting uBlock-compatible scriptlets at `.atDocumentStart`. Scriptlets install property traps on `window.ytInitialPlayerResponse` and `window.playerResponse` (stripping `adPlacements`, `playerAds`, `adSlots`) and intercept fetch/XHR player responses (`json-prune-fetch-response`) before YouTube's inline player scripts initialize.
- **CSP & Trusted Types Safe**: The injected scriptlet wrapper embeds domain checks natively without using `eval()` or `new Function()`, ensuring full compliance with YouTube's strict `Content-Security-Policy: require-trusted-types-for 'script'` policies.
- **Defensive Multi-Tier DOM Injection**: The cosmetic user script checks for `document.head || document.documentElement` immediately; if not yet parsed, it utilizes a `MutationObserver` on `document` to attach the style the exact microtask the root node is created, with `DOMContentLoaded` as a reliable fallback.
- **Strict Dot-Boundary Subdomain Decomposition**: Exact suffix decomposition (`parts.slice(i).join('.')`) ensures subdomains like `m.youtube.com` and `www.youtube.com` match `youtube.com` rules without risk of false-positive substring matches (e.g., `notyoutube.com` never matches).
- **One-Time Persistent Compilation**: Automatically checks `WKContentRuleListStore.default().lookUpContentRuleList` to reuse WebKit's on-disk compiled bytecode across app launches. Rule compilation happens only on the first cold launch or after rule updates, avoiding repeated overhead.
- **Thread-Safe & Zero-Regression Multi-Tab Cold Launch**: Ensures that rapid tab openings immediately at launch cannot bypass the blocker; WebViews are never initialized without rules, cosmetic scripts, and scriptlets attached.

### What it does NOT do (Scope & Disclaimers):
- **General Scriptlets for All Sites**: This pass focuses specifically on YouTube in-stream video ad defusal as a proof of concept for the scriptlet pipeline. General scriptlets for arbitrary third-party websites remain out of scope for this pass.
- **No Separate Scriptlet UI**: There is currently no UI indicator distinguishing "scriptlet active" from the existing shield/stats popover.
- **No Dynamic / Live Rule Updates at Runtime**: Rules and scriptlets are not fetched over the air at runtime; they are compiled developer-side and shipped with the application.
- **Cat-and-Mouse Staleness Risk**: Unlike static network domains or cosmetic CSS classes, YouTube actively and frequently updates its player codebase, variable names, and anti-adblock detection logic. Scriptlet-based player response defusal is inherently a cat-and-mouse mechanism that can break when YouTube alters its internal player contracts. It requires periodic re-verification and regeneration via `./generate_rules.sh` independent of the EasyList cycle.

---

## Tooling & Architecture: Why `adblock-rust` CLI Was Chosen

During evaluation between the Rust CLI vs the published npm/WASM build (`adblock-rs`):
1. **API Capability**: The npm package `adblock-rs` only exposes the runtime matching engine (`Engine`) for Node.js. It does **not** expose the Apple Safari/WebKit `content-blocking` conversion module.
2. **Setup Cost**: The npm package actually compiles native Rust code via `cargo build` during its `postinstall` hook anyway, so an active Rust toolchain is required in both cases.
3. **Native Support**: The native `adblock` Rust crate (`v0.13.3`) includes built-in, first-class support for `features = ["content-blocking"]`. It provides exact `WKContentRuleList`-compatible rule definitions (`CbRule`, `CbTrigger`, `CbAction`, and `ignore_previous_fp_documents`), parsing ~145,000 raw rules and outputting verified Safari JSON, cosmetic filters, and resolved scriptlet snippets in under 110 milliseconds.

Consequently, `tools/rule-converter/` was built as a dedicated Rust CLI using the `adblock` crate.

---

## Developer Workflow: Updating Rules

`generate_rules.sh` is a **developer-time tool**, not something the app runs at runtime (similar to how `xcodegen` is a developer-only tool for this project).

To update the rules to the latest EasyList, EasyPrivacy, and uBlock Origin snapshots:

```bash
./generate_rules.sh
```

### What `generate_rules.sh` does:
1. Downloads the latest `easylist.txt`, `easyprivacy.txt`, `filters.txt` (uBlock Origin), `quick-fixes.txt` (uBlock Origin), and `brave-resources.json` using `curl` with retries into a secure temporary directory.
2. Validates line counts to ensure downloads are complete and uncorrupted (>30k EasyList lines, >20k EasyPrivacy lines, >1k uBlock lines).
3. Runs `tools/rule-converter` to transform ABP network syntax into WebKit content-blocking JSON, domain-specific cosmetic CSS selectors, and resolved YouTube defusal scriptlets.
4. Validates the network rules with WebKit's native `WKContentRuleListStore.compileContentRuleList` to guarantee that WebKit accepts the rules.
5. Validates the cosmetic filters JSON structure and domain coverage (>5,000 domains).
6. Validates that `scriptlets.json` is a valid dictionary containing non-empty, fully compiled JavaScript snippets for `youtube.com`.
7. Atomically writes results to:
   - `rules/content-blocker.json`
   - `rules/cosmetic-filters.json`
   - `rules/scriptlets.json`
8. Cleans up all temporary raw list files.

After running `generate_rules.sh`, commit the updated `rules/` files to git.
