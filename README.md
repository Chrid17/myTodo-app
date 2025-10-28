# my_project

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web notifications & custom sound

This app supports scheduled reminders on web while the page/tab is open. Custom notification sound requires a short audio file in the web assets.

Steps to enable sound on web (GitHub Pages):

1. Add a short audio file (e.g. a 0.5-2s MP3) to the project at `assets/sounds/notify.mp3`.
2. Build the web app so the asset is bundled:

```powershell
flutter build web
```

3. Deploy the contents of `build/web` to GitHub Pages (your existing deployment process).

4. Open the app in the browser and interact with the page (tap/click). Use the top-right volume button to "Enable & Test" which primes audio playback.

Notes:
- Browser autoplay rules require a user gesture before audio can play programmatically. The app provides a button to satisfy this.
- Scheduled reminders on web only fire while the tab is open. To receive notifications when the app is closed you must implement web push (FCM or Push API) and a server-side scheduler — this requires additional setup.

