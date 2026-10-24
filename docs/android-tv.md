# Android TV development

The Android app declares a TV launcher entry and an optional Leanback feature,
so the same application can run on phones and Android TV. On TV, it uses a
landscape layout, directional navigation and visible keyboard focus. TV detection
uses Android's television UI mode or Leanback system feature, not screen size.

## Build and install

Follow the SDK, GitHub Packages and signing setup in the root README first.
The project requires Flutter 3.47.7 or newer, Android SDK 36 and NDK 29.0.14206865.
Use a compatible JDK such as Java 17 or 21. The native VPN dependency requires a
GitHub token with `read:packages`, provided as `GPR_KEY` or the Gradle `gpr.key`
property; never commit the token.

For a Shield with ARM64 support:

```sh
make init
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
adb connect <shield-ip>:5555
adb -s <shield-ip>:5555 shell getprop ro.build.version.sdk
adb -s <shield-ip>:5555 shell getprop ro.product.cpu.abilist
adb -s <shield-ip>:5555 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Android 8.0 (API 26) or newer is required. Verify the device's ABI before choosing
the build target. A debug APK cannot replace an existing app signed with another
key. Do not uninstall an existing app without backing up its configuration.

Enable network debugging on the Shield and accept the Mac's authorization prompt
on the TV. If macOS reports `No route to host` even on the same subnet, check the
device address, network isolation and the terminal/app's Local Network permission.

## Import a server from another device

On TV, choose **Import from phone or computer** on the empty Servers screen, or
use the import action at the top of an existing server list. The TV opens a local
page for five minutes and displays its address, QR code and a six-digit pairing
code. Connect the phone or computer to the same home network:

1. Scan the QR code, or open the displayed HTTP address in a browser and enter
   the pairing code. A QR scan supplies its own session credential.
2. Paste the complete `tt://?…` server link and select **Send to TV**.
3. Review the server name, address, certificate domain and protocol on the TV,
   then select **Add** with the remote. Importing does not start the VPN.

The browser page is served by the TV; no account, cloud upload or additional
phone app is required. Use a trusted home network: this local HTTP transfer is
not encrypted. The session closes after receiving one valid configuration, on
timeout, after five incorrect pairing codes, when leaving the import screen, or
when the TV app goes into the background. Canceling the review saves nothing.

This imports server settings only. It uses the existing TrustTunnel link decoder
and the default routing profile; it does not import routing rules or TOML files.
As with existing deep links, only the first endpoint address is retained.
Credentials are preserved verbatim, duplicate DNS entries are removed and
duplicate server names receive a numeric suffix. All server records are saved in
one database transaction.

If the browser cannot connect, check that both devices are on the same network
and that guest Wi-Fi/client isolation is disabled. Start a fresh import session
after changing networks or returning to the app. The first version requires a
private IPv4 address on Wi-Fi or Ethernet.

## Device acceptance checks

Run these with only the standard remote, without a mouse or touchscreen:

- Open TrustTunnel from the TV launcher; check its banner, landscape orientation
  and visible initial focus.
- Move between the navigation rail and page content in both directions. Switch
  between Servers, Routing and Settings, including empty lists.
- Import a test link using the QR code and separately using the address and
  pairing code. Reject a malformed link, then retry with a valid one. Confirm
  with the remote, relaunch the app and check the saved fields. Repeat a server
  name without overwriting the original. Cancel a received server and check
  that it is absent. Verify that Back, Home, expiry and successful receipt close
  the HTTP listener; no live endpoint should remain in the background.
- Add a server. Reach each field, open and close the on-screen keyboard with OK
  and Back, and move to the next field after the keyboard closes. Reopen the
  keyboard on an already focused field. Select the protocol and routing profile,
  scroll to the end of the form and save.
- Edit an existing server and toggle checkboxes, radio options and switches.
  Check that focus remains visible and that one OK press performs one action.
- Open dialogs, cancel with Back, and verify that navigation continues on the
  underlying screen. Check Back from a nested page and then from the app root.
- If using a custom certificate, verify that the device's file picker can import
  it with the remote.
- Accept the Android VPN permission dialog, connect to a real TrustTunnel server
  and verify actual traffic and DNS resolution. Disconnect and reconnect.
- Leave the app for another TV application, then sleep and wake the Shield.
  Confirm the VPN state and connectivity after returning. Recheck after a reboot.

Widget tests cover focus and remote activation, but do not validate the system
keyboard, VPN service, native libraries or Shield firmware. Physical-device
checks are required before claiming complete TV support or publishing a TV build.

## UI state checks

Check the actual rendered control, not only the colors resolved by its theme:
Flutter can paint an ink overlay above a button border. The shared button themes
use translucent state overlays and a three-pixel focus border so the outline
remains visible during focus, hover and press. Focus does not change the control's
outer bounds. Disabled styling takes priority over interactive states.

- Follow focus through the server row, connection button, import action and Add
  server button. Connected/disconnected is the button's selected state; the
  focus border must be distinguishable from that state.
- Connect, cancel, reconnect and disconnect. The connection button must retain
  focus when its icon changes; only the progress icon should rotate.
- Check both buttons on the empty Servers screen, including the lower outlined
  button. Move off a button and confirm that its focus border disappears while
  its normal outline remains.
- Open menus and dialogs, press and release OK, and return with Back. Check
  focused, disabled, selected and validation-error states as well as idle ones.
- Use long profile names and increased system font size. Popup labels must wrap
  inside their item; an open profile dropdown must show the complete label
  without overlapping adjacent items. Its collapsed label can use an ellipsis.
- Scroll a populated connection log with Up/Down, then move Left back to the
  navigation rail. The focused log viewport must remain visibly marked.
- On short viewports, follow focus to actions below the fold and verify that
  they scroll into view without the page jumping back on a rebuild.

Regression tests include rendered focus-border contrast, stable button bounds,
VPN state transitions, remote scrolling and layout with long text/increased
text scale. Recheck these states on hardware when changing shared themes or
page wrappers.

The browser import page has additional regression tests for QR/PIN authorization,
history restoration and independent device clocks. Run these with Node.js 18 or
newer (no npm packages are needed):

```sh
node --test test/feature/server_import/local_import_page_test.mjs
```
