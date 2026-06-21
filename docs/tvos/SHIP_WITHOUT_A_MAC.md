# Ship & test on real devices — without a Mac

Goal: install **Amelia's Bus Adventure** on your **iPhone, iPad, and Apple TV**
and play it, using only a browser/phone — **no Mac required**. GitHub's free
macOS runners build, sign, and upload the app; you install it from the
**TestFlight** app on each device.

## The one cost you can't avoid

- **GitHub side = free.** This repo is public, so macOS Actions minutes are free
  and unlimited. The build/sign/upload is 100% automated here.
- **Apple side = $99/year.** Installing on a *real* device (and **especially**
  Apple TV, which has **no** sideloading) requires the **Apple Developer
  Program**. There is no free, no-Mac way to get a build onto an Apple TV. The
  $99/yr enrollment + **TestFlight** is the path. (This is decision **D-SIGN-1**.)

Everything below assumes you've decided to enroll. You can do all of it from an
iPhone/iPad + a web browser.

---

## Part A — one-time setup (~30–45 min, no Mac)

### A1. Enroll in the Apple Developer Program
1. Install the **Apple Developer** app on your iPhone/iPad (App Store), or go to
   <https://developer.apple.com/programs/enroll/>.
2. Enroll as an individual ($99/yr). Identity verification is done in the app.
3. After approval (often minutes to a day), you have access to **App Store
   Connect** at <https://appstoreconnect.apple.com> (works in a mobile browser).

### A2. Create an App Store Connect API key (used for signing + upload)
In App Store Connect → **Users and Access** → **Integrations** tab →
**App Store Connect API**:
1. Create a **Team Key** with role **App Manager** (or Admin).
2. **Download the `.p8` file** — you can only download it **once**. Keep it safe.
3. Note the **Key ID** (e.g. `A1B2C3D4E5`) and the **Issuer ID** (a UUID near
   the top of the keys page).

### A3. Find your Team ID
In App Store Connect → **Membership details** (or
<https://developer.apple.com/account> → Membership). Copy the **10-character
Team ID** (e.g. `9ABCDE1234`).

### A4. Create the two app records
In App Store Connect → **Apps** → **＋** → **New App**, twice:
1. **iOS** app — pick a unique **Bundle ID** you own, e.g.
   `com.calebsmith.ameliabus`. (Platforms: iOS.)
2. **tvOS** app — another unique Bundle ID, e.g.
   `com.calebsmith.ameliabus.tv`. (Platforms: tvOS.)

> Tip: the bundle ids must be globally unique and start with your reverse-domain.
> You don't need to own a real domain — just keep it consistent and unique.
> Kids-category and other store metadata can be set later; not needed for
> TestFlight.

### A5. Put the secrets into GitHub (in a protected environment)
In the GitHub repo → **Settings** → **Environments** → **New environment** named
exactly **`release`**:
1. Under **Deployment protection rules**, add **Required reviewers** = yourself.
   (This makes every release run pause for your one-tap approval, and is what
   keeps the signing secrets locked to this workflow.)
2. Add these **Environment secrets** (Settings → Environments → release →
   *Add secret*):

   | Secret name      | Value                                                        |
   |------------------|--------------------------------------------------------------|
   | `ASC_API_KEY_P8` | The **entire contents** of the `.p8` file (paste as-is, multi-line) |
   | `ASC_KEY_ID`     | The Key ID from A2                                            |
   | `ASC_ISSUER_ID`  | The Issuer ID from A2                                         |
   | `APPLE_TEAM_ID`  | The Team ID from A3                                           |
   | `IOS_BUNDLE_ID`  | The iOS bundle id from A4 (e.g. `com.calebsmith.ameliabus`)  |
   | `TVOS_BUNDLE_ID` | The tvOS bundle id from A4 (e.g. `com.calebsmith.ameliabus.tv`) |

   > Paste the `.p8` **text** directly (open it as a text file and copy all of it,
   > including the `-----BEGIN PRIVATE KEY-----` lines). No base64 needed.

### A6. Set up signing storage (fastlane match)

App Store (TestFlight) builds need a **distribution certificate + provisioning
profile**. We use **fastlane match**, which creates them from your API key and
stores them *encrypted* in a private repo so every build reuses them — **no Mac,
no registered devices**. (Apple requires a registered *device* only for
*development* signing, which TestFlight doesn't use; distribution signing needs
none — that's why match is the clean no-Mac path.)

1. Create a **new, PRIVATE** GitHub repo to hold the encrypted certs, e.g.
   `amelia-certs`. Leave it empty.
2. Create a **Personal Access Token** GitHub can use to read/write that repo
   (Settings → Developer settings → *Fine-grained tokens* → grant **Contents:
   Read and write** on just that repo; or a classic token with `repo` scope).
3. Compute the basic-auth value: it's the base64 of `your-username:the-token`.
   On any computer/phone with a terminal: `printf 'USER:TOKEN' | base64`. (Or use
   any base64 tool.)
4. Add these **Environment secrets** to the same **`release`** environment:

   | Secret name                     | Value                                                       |
   |---------------------------------|-------------------------------------------------------------|
   | `MATCH_GIT_URL`                 | HTTPS url of the private certs repo (e.g. `https://github.com/you/amelia-certs.git`) |
   | `MATCH_PASSWORD`                | A passphrase you choose (encrypts the stored certs — keep it safe) |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | The base64 string from step 3                               |

5. **Run the one-time bootstrap:** GitHub → **Actions** → **match-setup** →
   **Run workflow** → **Approve**. This creates the distribution cert + both App
   Store profiles and pushes them (encrypted) to your certs repo. You only do
   this once (re-running is safe).

That's the whole one-time setup.

---

## Part B — make a build (each time; from phone or browser)

1. GitHub repo → **Actions** → **release-testflight** → **Run workflow**.
2. Choose **platform**: `both`, `ios`, or `tvos` → **Run workflow**.
3. The run pauses on the **`release` environment** → tap **Review deployments** →
   **Approve**. (This is the protection rule from A5.)
4. It builds, signs, and uploads to TestFlight (~8–15 min). Green check = done.

## Part C — install on your devices (no Mac, ever)

1. After a successful run, open **App Store Connect → your app → TestFlight**.
   The new build shows "Processing" for ~5–15 min, then is ready.
2. Add yourself as an **Internal Tester**: TestFlight tab → **Internal Testing**
   → add an internal group → add your Apple ID (must be a user in
   *Users and Access*). Internal builds need **no Apple review** and appear almost
   immediately.
3. On each device, install the **TestFlight** app:
   - iPhone / iPad: App Store → TestFlight.
   - **Apple TV**: App Store on the Apple TV → search **TestFlight** → install.
4. Open TestFlight, sign in with that Apple ID, and you'll see **Amelia** →
   **Install** → play. New builds arrive in TestFlight automatically.

---

## Handy to know
- **Internal testing** (up to 100 testers who are users on your account) is
  instant and needs no review. Use it for yourself/family. *External* testing
  needs a quick Apple review — not needed for your own devices.
- TestFlight builds **expire after 90 days**; just run the workflow again.
- **Build numbers auto-increment.** fastlane reads the latest build already on
  TestFlight and uploads one higher, so re-running never collides. (To bump the
  human-facing *version*, edit `MARKETING_VERSION` in `AmeliaTV/project.yml`.)
- **App icons are included** as friendly placeholders (a yellow bus under a sunny
  sky) so uploads pass Apple's validation. Real art is decision **D-ART-1**;
  regenerate/replace them via `python3 AmeliaTV/Tools/make_icons.py` (the
  asset-catalog names stay the same, so no project changes needed to swap art).
- You can run `ios`, `tvos`, or `both` independently.

## If a run fails
The first real run sometimes needs a small tweak (Apple's signing is fiddly).
Open the failed job's logs in the Actions tab — the error is usually about the
bundle id, team, or the app record not existing yet. Paste the error to me and
I'll fix the workflow; I just can't dry-run it without your account.

## Why no fully-free option?
- **Apple TV**: no sideloading exists. TestFlight (paid) or Xcode-on-a-Mac are
  the only ways. So the paid program is required for tvOS regardless.
- **iPhone/iPad**: a free Apple ID can sideload via tools like AltStore, but it
  needs a *computer* running a helper app, re-signs every 7 days, and can't be
  driven from CI. Not a clean no-Mac flow. TestFlight is far simpler and also
  covers the Apple TV, so we standardize on it.
