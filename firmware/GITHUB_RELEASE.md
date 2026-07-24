# Publishing BLINK firmware on GitHub

Use a public GitHub release with a compiled ESP32-C3 `.bin` asset. The BLINK
app calls GitHub's `releases/latest` endpoint, selects the first asset ending
in `.bin`, downloads it, and transfers it to the robot using BLE OTA.

The included `.github/workflows/release.yml` does this automatically whenever
a tag such as `v3.1.1` is pushed. It publishes both:

- `BLINK_Robot-v3.1.1.bin` — selected by the app for robot updates.
- `BLINK-Companion-v3.1.1.apk` — companion app configured to check that same
  GitHub repository.

For a manual release, compile `firmware/BLINK_Robot` for **ESP32C3 Dev Module**
and upload the generated `.bin` to the GitHub release. Build the app with:

```powershell
flutter build apk --release --dart-define=BLINK_GITHUB_REPOSITORY=OWNER/REPOSITORY
```

Never upload a `.ino` source file as a firmware release asset; BLINK needs the
compiled `.bin`. The receiving robot must already have v3.1.0 installed once
over USB to enable BLE OTA.
