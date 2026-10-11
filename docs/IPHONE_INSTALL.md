# First iPhone installation

Target: **iPhone X, iOS 16.7.16**. Use **AltStore Classic** with AltServer on
Windows. Follow the [official Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
for current downloads and troubleshooting.

## Prepare AltStore

1. Install the Apple iTunes and iCloud versions specified by AltStore's guide.
   The standard instructions use Apple's installers rather than Microsoft
   Store versions; follow its alternate troubleshooting instructions if needed.
2. Install and start AltServer on Windows.
3. Connect the iPhone by USB, unlock it, and trust the computer. Enable Wi-Fi
   sync in iTunes if you want wireless refreshes.
4. Use AltServer's system-tray menu to install AltStore on the iPhone. Enter
   your Apple account credentials in AltServer itself, never in this repository
   or an agent conversation.
5. Trust the developer profile under **Settings → General → VPN & Device
   Management**, as prompted.
6. Enable **Settings → Privacy & Security → Developer Mode**, restart the
   phone, and confirm when prompted. This is required for iOS 16 and later.

## Build and install RoadEye

1. In the GitHub repository, open **Actions → Mobile release → Run workflow**.
2. Wait for **Analyze and test** and **iOS release for AltStore** to succeed.
3. Download `RoadEye-iOS-<run-number>` from the run's artifacts. Extract the
   archive; the installable file is `build/altstore/RoadEye-unsigned.ipa`.
4. Transfer the IPA to the iPhone's Files app.
5. Keep AltServer running and reachable. In AltStore, open **My Apps**, tap
   **+**, and select the IPA. AltStore signs it with your personal account.
6. Open RoadEye from the Home Screen.

If installation fails, record the exact AltStore error and workflow run URL.
Confirm Developer Mode, profile trust, AltServer connectivity, and available
app slots/App IDs before changing app code.

## Milestone acceptance checklist

- RoadEye installs and opens without immediately closing.
- The screen displays **RoadEye is running**.
- Tapping **Check app** displays **App check passed**.
- The screen remains usable with larger text settings.
- Force-close and reopen the app; the check resets and works again.
- Restart the iPhone and reopen the app successfully.
- With networking disabled, the installed app still opens and the check works.

Record the build number, device, iOS version, date, and results in
`docs/HANDOFF.md`. A CI build alone does not prove this milestone is complete.

With a free Apple account, sideloaded apps expire after seven days. Refresh
RoadEye and AltStore before expiry while AltServer is available. See
[AltStore's getting-started guide](https://faq.altstore.io/altstore-classic/your-altstore).
