# iPhone/iPad IPA Build Without a Mac

This repository ships an iPhone/iPad app and Widget. It does not ship a macOS
app. A Mac is still required somewhere in the build path because Apple only
ships the iPhone/iPad SDK and archive tools with Xcode. If you do not own a
Mac, the manual GitHub Actions workflow provides that macOS build host.

## Artifact Types

Run **Build re-signable iOS IPA** from the GitHub Actions page on the `iOS`
branch. It produces one artifact ZIP containing two IPA files:

```text
AoxiangAssistant-sideload-re-signable.ipa
AoxiangAssistant-full-widget-re-signable.ipa
```

Both use the conventional `Payload/AoxiangAssistant.app` structure and are
deliberately **unsigned**. Neither can be installed as downloaded. Start with
`AoxiangAssistant-sideload-re-signable.ipa` when using a normal iPad
self-signing tool: it contains only the main app and does not require signing a
nested extension or authorizing an App Group. The offline app remains usable,
but Widget/background snapshot features are absent from this variant.

Use `AoxiangAssistant-full-widget-re-signable.ipa` only when the signing tool
can sign the host app and its embedded Widget and authorize the App Group.

No Apple ID, certificate, private key, password, mobile device profile, or
WebView session is stored in this repository or the workflow. The workflow
uses a temporary macOS directory and uploads only the IPA artifact for seven
days.

The workflow also accepts three non-secret identifiers: the host App ID, the
Widget App ID, and the App Group. Leave the defaults only when your signing
team owns those exact identifiers. Otherwise enter the identifiers that already
exist in your Apple Developer team; the archive stamps the same values into
both target Info.plists and entitlements. These fields do not create an App ID
or grant the capability by themselves.

## iPad-Only Workflow

No personal Mac is required. From Safari on the iPad, open this repository on
GitHub, switch to the `iOS` branch, open **Actions**, select **Build re-signable
iOS IPA**, and run the workflow for that branch. When it finishes, download the
artifact ZIP, extract both IPA files, and start with the `sideload` file in the
signing tool already trusted on the iPad.

Do not enter signing credentials, Apple ID details, certificates, profiles, or
passwords into a GitHub issue, workflow input, repository secret, fixture, or
source file. The signing tool must support nested extensions and sign both the
host app and `AoxiangAssistantWidget.appex` only for the `full-widget` file;
otherwise use the `sideload` file.

## Signing Requirements

For the signer screen, keep the “删除 Plugins” switch disabled. The other
iPad compatibility switches do not enable Widget support. The full package
must be re-signed in this order: the nested Widget (and any nested framework),
then the host app. A tool that only signs the top-level app can produce an
IPA-shaped file, but iPadOS will reject it or omit the extension.

There is no iPad Settings switch that can add a missing extension or App Group.
After signing, install the full-widget IPA, open the main app once so it writes
a snapshot, and add 翱翔助手 from the Home Screen widget gallery. If the
Widget does not appear, inspect the signed IPA rather than changing display
settings.

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

The repository includes scripts/verify_signed_ios_ipa.sh for a macOS shell
that checks the nested code signatures, provisioning profiles, Bundle IDs and
App Group before installation:

    bash scripts/verify_signed_ios_ipa.sh signed-full-widget.ipa \
      com.example.aoxiang \
      com.example.aoxiang.widget \
      group.example.aoxiang

The workflow first runs both Swift Package suites, then runs one device archive
with `CODE_SIGNING_ALLOWED=NO`, packages both variants, and verifies that the
sideload IPA has no `PlugIns` entry while the full IPA has the Widget entry. It
does not claim a signed device install succeeded. After self-signing, install
the sideload IPA on a test iPad and verify:

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
