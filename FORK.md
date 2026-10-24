# About this fork

This repository is a fork of
[TrustTunnel/TrustTunnelFlutterClient](https://github.com/TrustTunnel/TrustTunnelFlutterClient).
Its `master` branch is the upstream `master` plus the changes listed below.
Upstream changes are merged in regularly.

If upstream adds equivalent features, this fork will no longer be needed.

## Differences from upstream

### Android TV support

- The app appears in the Android TV launcher with its own banner.
- On TV it uses a landscape layout and works with the standard remote:
  directional navigation, visible focus and Select key handling.
- Buttons, inputs, lists, dropdowns and snack bar actions have visible focus states.

### Server import from a phone or computer

- On TV, the Servers screen offers **Import from phone or computer**.
- The TV shows a QR code, a local address and a pairing code. Open the page on a
  phone or computer on the same network and paste a `tt://` server link.
- The server is saved only after you confirm it on the TV.

See [docs/android-tv.md](docs/android-tv.md) for build, install and usage details.

### Bug fixes

- Android Back closes an open dropdown before leaving a form or showing the
  "Discard changes?" dialog. Submitted upstream as
  [TrustTunnel/TrustTunnelFlutterClient#78](https://github.com/TrustTunnel/TrustTunnelFlutterClient/pull/78).

## Syncing with upstream

```sh
git fetch upstream
git merge upstream/master
```

Merge, don't rebase: the fork's history is published and should not be rewritten.
