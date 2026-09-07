# iPhone/iPad IPA Build Without a Mac

This repository ships an iPhone/iPad app and Widget. It does not ship a macOS
app. A Mac is still required somewhere in the build path because Apple only
ships the iPhone/iPad SDK and archive tools with Xcode. If you do not own a
Mac, the manual GitHub Actions workflow provides that macOS build host.

## Artifact Type

Run **Build re-signable iOS IPA** from the GitHub Actions page on the `iOS`
branch. It produces an artifact containing:

```text
AoxiangAssistant-re-signable.ipa
```

The artifact has the conventional `Payload/AoxiangAssistant.app` structure and
includes `AoxiangAssistantWidget.appex`. It is deliberately **unsigned**. It
cannot be installed as downloaded. Download it on the iPad, extract the GitHub
artifact ZIP, then use your own trusted self-signing tool and signing identity
to sign the host app and its embedded Widget before installation.

No Apple ID, certificate, private key, password, mobile device profile, or
WebView session is stored in this repository or the workflow. The workflow
uses a temporary macOS directory and uploads only the IPA artifact for seven
days.

## iPad-Only Workflow

No personal Mac is required. From Safari on the iPad, open this repository on
GitHub, switch to the `iOS` branch, open **Actions**, select **Build re-signable
iOS IPA**, and run the workflow for that branch. When it finishes, download the
artifact ZIP, extract `AoxiangAssistant-re-signable.ipa`, then use the signing
tool already trusted on the iPad.

Do not enter signing credentials, Apple ID details, certificates, profiles, or
passwords into a GitHub issue, workflow input, repository secret, fixture, or
source file. The signing tool must support nested extensions and sign both the
host app and `AoxiangAssistantWidget.appex`; otherwise stop before installing.

## Signing Requirements

Your signing method must sign every executable bundle together:

- `AoxiangAssistant.app`;
- `AoxiangAssistant.app/PlugIns/AoxiangAssistantWidget.appex`.

The host and Widget must use compatible bundle identifiers and profiles. The
project declares the same App Group,
`group.cn.nwpu.aoxiang-assistant`, in both targets. If your signing identity
cannot authorize that App Group, do not fabricate it or replace it with a
private directory. The app remains usable for offline import, viewing and
local editing, but it will show a clear warning; Widget snapshots and
background collection are disabled fail-closed because the Widget cannot read
the main app's private data.

Free/personal signing identities may expire quickly and may not authorize App
Groups. A paid Apple Developer team with the matching App Group capability is
needed for the full Widget experience. This is a signing limitation, not a
macOS product target.

## Build Verification

The workflow first runs both Swift Package suites, then runs a device archive
with `CODE_SIGNING_ALLOWED=NO` and verifies both bundle paths inside the IPA.
It does not claim a signed device install succeeded. After self-signing,
install the IPA on a test iPad and verify:

1. Android schedule backup imports without asking for credentials.
2. Home, grades, schedule and management views render local data and local
   edits survive an app restart.
3. The Widget reads only the shared snapshot when your signing profile supports
   the App Group.
4. Login and SMS occur only in the visible authentication screen; a background
   run that needs login or SMS leaves the last Widget snapshot unchanged and
   asks the user to open the app.

## Local Windows Tests

Windows cannot build the iPhone/iPad archive, but it can run portable Swift
tests after installing Swift for Windows and Visual Studio Build Tools with the
C++ workload. This repository includes:

```powershell
.\scripts\run_swift_tests_windows.ps1
```

The script discovers the installed Swift toolchain, configures the bundled
Windows SDK and invokes the Visual Studio C++ linker environment. It runs
`AoxiangCore` and `AoxiangApp` tests only; the GitHub macOS workflow remains
the authoritative device-archive check.
