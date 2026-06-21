# Apple Deployment Playbook (iOS / iPadOS / tvOS → TestFlight, no Mac)

A reusable, project-agnostic guide for shipping a native Apple app to **TestFlight**
from **GitHub Actions with no Mac**, using **fastlane + match**. Written after a
painful first run so future projects (and future Claude Code sessions) get it
right the first time.

> **Reuse note:** the private **certs repo** (e.g. `apple-certs`) and your App
> Store Connect API key are **reusable across every app and project**. One Apple
> Distribution certificate covers your whole team; match just stores one more
> provisioning profile per bundle id. New app = new bundle id + new app record +
> point `MATCH_GIT_URL` at the same `apple-certs` repo. Don't make a new certs
> repo per project.

---

## 0. Mental model (read this first — it prevents 80% of the pain)

1. **TestFlight uses _distribution_ signing, which needs ZERO registered
   devices.** Do **not** use Xcode "automatic signing" in CI — automatic signing
   tries to make a _development_ profile during archive, which **requires a
   registered device** (and a tvOS dev profile needs a registered _Apple TV_).
   That dead-end caused half our failures. Use **match** (distribution) instead.
2. **Registering devices ≠ TestFlight access.** Anyone you add as a TestFlight
   tester installs on any device by signing in — device registration is only a
   _build-time_ concern for development signing, which we avoid entirely.
3. **One App Store Connect API key (.p8)** authenticates everything: match,
   xcodebuild provisioning, and the TestFlight upload. No certificates or
   profiles to manage by hand.
4. **Secrets live on the workflow's repo**, in a protected `release`
   _environment_ — NOT in the certs repo (the certs repo just stores files).

---

## 1. Best practices for the agent (Fastfile / workflow patterns)

These are the exact things that broke. Bake them in from the start.

### Signing
- **Use `match(type: "appstore")`**, manual signing on the build. Never rely on
  automatic signing in CI.
- **Bootstrap once, then read-only.** A separate manual workflow runs
  `match(readonly: false)` for all bundle ids **sequentially in one job** (they
  share one distribution cert — parallel jobs race and can blow the 2-cert
  limit). The release workflow runs `match(readonly: true)`.
- **Apply signing to the _app target only_**, never as global build settings.
  Global `PROVISIONING_PROFILE_SPECIFIER`/`CODE_SIGN_IDENTITY` also hit library
  targets (e.g. a SwiftPM package) → *"X does not support provisioning
  profiles."* Use:
  ```ruby
  update_code_signing_settings(
    use_automatic_signing: false, path: "App.xcodeproj",
    targets: [scheme],                       # app target only
    team_id: ENV["APPLE_TEAM_ID"], bundle_identifier: bundle_id,
    code_sign_identity: "Apple Distribution", profile_name: profile_name
  )
  ```
- **Read the profile name from match, don't reconstruct it.** match names
  **non-iOS** profiles with a platform suffix (`match AppStore <id> tvos`).
  Use `lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING][bundle_id]`.
- **Call `setup_ci`** at the top of any lane that installs certs (temp keychain
  on the runner).

### xcodebuild / xcargs
- **`xcargs` is a raw shell string** — quote any value containing spaces
  (`CODE_SIGN_IDENTITY="Apple Distribution"`). Unquoted → *"Unknown build action
  'Distribution'."* Prefer setting per-target signing via
  `update_code_signing_settings` and keep xcargs to project-wide flags only.
- If you pass the API key to xcodebuild directly
  (`-authenticationKeyPath`), the path **must be absolute**. Relative paths
  double under fastlane's working dir (`fastlane/fastlane/AuthKey.p8`).

### App config / assets
- **Provide an app icon before the first upload.** iOS needs a 1024² icon; tvOS
  **requires** layered **Brand Assets** (App Icon + Top Shelf) or the archive
  fails validation. Generate placeholders programmatically so art never blocks.
- Set `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (local/no-custom-crypto
  apps) so TestFlight stops asking export-compliance every build.
- **Auto-increment the build number**: `latest_testflight_build_number(...) + 1`
  (fall back to 1). Hardcoded build numbers fail on the _second_ upload.

### Workflow hygiene
- Trigger releases with **"Run workflow"** (fresh), never **"Re-run jobs"** on an
  old run — a re-run replays the _old commit_ and silently lacks your latest fix.
- `workflow_dispatch` only shows on the **default branch** — merge to `main`
  before the button appears / picks up changes.
- **Print the build log on failure.** xcbeautify hides the real error; add an
  `if: failure()` step that greps `~/Library/Logs/gym/<Scheme>-<Scheme>.log` for
  `error:|validat|icon|provision`. Saves whole debugging round-trips.
- Keep signing secrets in a **protected `release` environment**; normal CI/PR
  workflows must never reference it.

---

## 2. One-time setup (you, from a browser/phone — ~30–45 min)

### A. Apple side
1. **Enroll** in the Apple Developer Program ($99/yr) — the *only* unavoidable
   cost; required for any real-device/Apple-TV install.
2. **App Store Connect API key**: Users and Access → Integrations → App Store
   Connect API → create a **Team Key** (role: App Manager). **Download the `.p8`
   once.** Note the **Key ID** and **Issuer ID**.
3. **Team ID**: developer.apple.com → Membership (10 chars).
4. **App records**: App Store Connect → Apps → ＋ for each platform. Pick a unique
   **Bundle ID** per platform, e.g. `com.you.app` (iOS) and `com.you.app.tv`
   (tvOS). Capabilities: leave **all off** unless the app truly needs one.
   > Note: the reverse-DNS goes in the **Bundle ID** field; the **Name** field is
   > a plain label and can't contain dots.

### B. Signing storage (match) — REUSABLE across all your apps
5. **Private** repo to hold encrypted certs, e.g. `apple-certs` (reuse the one
   you already have — don't make a new one per app).
6. A **fine-grained PAT** (github.com → Settings → **Developer settings** →
   Personal access tokens → Fine-grained) with **Contents: Read and write** on
   **only** that certs repo.
7. Compute `MATCH_GIT_BASIC_AUTHORIZATION` = base64 of `username:token`:
   - macOS/Linux: `printf 'USER:TOKEN' | base64`
   - Windows PowerShell:
     `[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('USER:TOKEN'))`

### C. Put secrets on the workflow repo (NOT the certs repo)
8. Repo → Settings → **Environments** → new env named exactly **`release`**
   (optionally add yourself as a required reviewer). Add:

   | Secret | Value |
   |---|---|
   | `ASC_API_KEY_P8` | full contents of the `.p8` |
   | `ASC_KEY_ID` / `ASC_ISSUER_ID` | from step 2 |
   | `APPLE_TEAM_ID` | from step 3 |
   | `IOS_BUNDLE_ID` / `TVOS_BUNDLE_ID` | from step 4 |
   | `MATCH_GIT_URL` | HTTPS url of the certs repo |
   | `MATCH_PASSWORD` | a passphrase you pick (encrypts the certs — **reuse the same one** for all apps sharing the repo) |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | from step 7 |

### D. Bootstrap + ship
9. Actions → **match-setup** → Run workflow → Approve (one-time; creates + stores
   the cert + profiles). Re-running is safe.
10. Actions → **release-testflight** → Run workflow (`both`/`ios`/`tvos`) →
    Approve. ~8–15 min → builds appear in App Store Connect → TestFlight.
11. TestFlight → add yourself as an **Internal Tester**; install the **TestFlight**
    app on each device (iPhone/iPad App Store; Apple TV App Store) and play.

### Reusing this for a NEW app later
- New bundle id + new App Store Connect app record.
- Point its `MATCH_GIT_URL` at the **same** `apple-certs` repo, same
  `MATCH_PASSWORD`. Run `match-setup` once for the new bundle id. Done — the
  distribution cert is shared; only a new profile gets added.

---

## 3. Failure → cause → fix cheat-sheet

| Symptom | Cause | Fix |
|---|---|---|
| `No Accounts / no provisioning profiles` | automatic signing, no creds | use match distribution signing |
| `team has no devices … provisioning profile` | automatic signing wants a dev profile | match (no devices needed) |
| `Unknown build action 'Distribution'` | unquoted space in xcargs | quote, or set via `update_code_signing_settings` |
| `X does not support provisioning profiles` | signing applied to a library target | scope to app target only |
| `No profile matching 'match AppStore …'` | tvOS profile name suffix | read `MATCH_PROVISIONING_PROFILE_MAPPING` |
| `-authenticationKeyPath must be absolute` | relative key path | make it absolute |
| 2nd upload: build number used | hardcoded build number | auto-increment from TestFlight |
| archive `Validate <App>.app` exit 65 | usually missing/invalid app icon | provide real icon assets; read the dumped gym log |

---

## 4. "Would a Mac mini make this easier?" — short answer: yes, but…

See the chat reply / `RISKS_AND_DECISIONS.md`. TL;DR: a Mac removes the need for
the CI signing gymnastics for **one-off** uploads (Xcode Organizer → *Distribute
App* handles signing in a GUI), and unlocks local Simulator + on-device testing,
which is the bigger day-to-day win. It does **not** replace this pipeline for
**automated** deploys — you'd still use match/fastlane and could hit the same
config issues. The pipeline above already works headlessly, so a Mac is a
quality-of-life upgrade, not a requirement.
