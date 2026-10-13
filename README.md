# Kdrop

AirDrop / NameDrop-style sharing for **iPhone and Android**, built with Flutter.

- **Touch to share:** hold two phones together. A glow ripples across both
  screens, then whatever you've picked is sent. If you haven't picked anything,
  you're offered a contact-card swap, like NameDrop.
- **Radar:** nearby phones orbit your avatar, and closer phones drift toward the
  centre. Tap one to send.
- Share **photos & videos, any file, your contact card, or text / links**.
- The receiver always gets an Accept / Decline prompt.
- Transfers go straight from phone to phone over the local network. Nothing is
  uploaded to the internet.

## How it works

```
            Bluetooth LE (proximity)                    Wi-Fi LAN (data)
 ┌────────┐  advertise UUID 4b44524f-…-<deviceId>  ┌────────┐
 │ Phone A│ ◀───────────── RSSI ─────────────────▶ │ Phone B│
 │        │                                        │        │
 │        │  mDNS  _kdrop._tcp  {id,name,platform} │        │
 │        │ ◀────────────── discovery ────────────▶ │        │
 │        │  POST /v1/offer  → Accept / Decline    │        │
 │        │  PUT  /v1/files/<token>/<i>  (stream)  │        │
 └────────┘ ─────────────── HTTP ────────────────▶ └────────┘
```

1. **Discovery (Wi-Fi):** every phone runs a small HTTP server and announces it
   over Bonjour/mDNS (`_kdrop._tcp`, via
   [bonsoir](https://pub.dev/packages/bonsoir)). Phones on the same network show
   up on each other's radar.
2. **Proximity (Bluetooth):** every phone advertises a BLE service UUID that
   carries its 12-hex-character device id (iOS only allows service UUIDs in
   advertisements, so the id goes inside the UUID). It also scans for the
   others. `ProximityDetector` smooths the noisy RSSI with an exponential
   moving average. It fires a *touch* after several consecutive readings above
   the threshold (default **-40 dBm**). Hysteresis and a cooldown keep it from
   firing again while the phones are still held together.
3. **Transfer (HTTP):** the sender posts an *offer*, and the request stays open
   until the receiver taps Accept or Decline. Contacts and text travel inside
   the offer. Files are then streamed one at a time with progress, and the
   receiver checks the sizes and cleans the file names.

## Running it

```bash
flutter pub get
flutter run            # on a real device
flutter test           # unit + widget + loopback transfer tests
```

You need two real phones on the **same Wi-Fi network** with **Bluetooth on**.
Emulators and simulators have no BLE, so touch-to-share won't trigger there.
Long-press a device on the radar to play the touch animation and the
contact-swap flow without Bluetooth.

**iOS:** open `ios/Runner.xcworkspace`, set your signing team, and run on a
device. The first launch asks for Bluetooth and Local Network access. Both are
required. Received files appear in **Files › On My iPhone › Kdrop**.

**Android:** Android 12+ asks for "Nearby devices". Android 11 and older ask
for location, which BLE scanning needs on those versions.

### Calibrating touch sensitivity

RSSI depends on the phone model and case. Open **Settings › Touch
sensitivity**, hold another phone against yours, and watch the live signal
readout. Move the slider until it reads *touching* only when the phones are
really touching.

## Project layout

```
lib/
  main.dart                       app entry, onboarding vs home
  src/kdrop_controller.dart       glue: discovery + proximity + transfers + UI events
  src/core/
    protocol.dart                 service type, BLE UUID <-> device id
    proximity_detector.dart       RSSI smoothing / touch detection (pure Dart)
    offer.dart, peer.dart, contact_card.dart (vCard 3.0)
  src/services/
    discovery_service.dart        mDNS broadcast + browse (bonsoir)
    proximity_service.dart        BLE advertise (flutter_ble_peripheral) + scan (flutter_blue_plus)
    transfer_server.dart          HTTP receiver
    transfer_client.dart          HTTP sender with progress + cancel
    settings_store.dart           device id / name / contact / sensitivity
  src/ui/
    home_screen.dart              radar, share tray, touch flow
    widgets/touch_glow.dart       the NameDrop-style glow + ripple animation
    widgets/radar_view.dart       pulsing radar with peer bubbles
    sheets.dart                   accept prompt, touch card, received items
    settings_screen.dart, onboarding_screen.dart, received_screen.dart
test/                             core logic, real HTTP transfers over loopback, widgets
```

## Known limitations / next steps

- **Same network required.** There's no Wi-Fi Direct / AWDL fallback yet.
  Phones on different networks (or with client isolation turned on) can't see
  each other.
- **Foreground only.** iOS stops BLE advertising in the background, so Kdrop
  needs to be open on both phones.
- **Unencrypted on the LAN.** Transfers use plain HTTP on the local network.
  Adding TLS with a key exchanged over BLE would be the next hardening step.
- Received photos are saved in the app's folder. Saving them straight to the
  gallery is not built yet.
