# iOS Notifications Checklist

The following fixes have been applied to your iOS project:

## ✅ Completed
- **AppDelegate.swift** – Added `UserNotifications` import and remote notification registration
- **Runner.entitlements** – Push Notifications capability (`aps-environment`)
- **GoogleService-Info.plist** – Firebase config (already present)
- **Xcode project** – Entitlements and `GoogleService-Info.plist` added to the project
- **Info.plist** – Background modes (`remote-notification`, `fetch`) already configured

## ⚠️ Required: Upload APNs Key to Firebase

Push notifications will not work on iOS until you upload an APNs Authentication Key to Firebase:

### Step 1: Create an APNs key in Apple Developer Portal
1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Click **+** to create a new key
3. Name it (e.g. "My Todo App Push")
4. Check **Apple Push Notifications service (APNs)**
5. Click **Continue** → **Register**
6. Download the `.p8` file (you can only download it once; store it safely)
7. Note the **Key ID** shown on the page

### Step 2: Upload to Firebase
1. Go to [Firebase Console](https://console.firebase.google.com) → **myTodo-app**
2. Click the gear icon → **Project settings**
3. Open the **Cloud Messaging** tab
4. In **Apple app configuration**, select **my_project (ios)**
5. Under **APNs Authentication Key**, click **Upload**
6. Upload your `.p8` file
7. Enter the **Key ID**
8. Enter your **Team ID** (from [Apple Developer Membership](https://developer.apple.com/account))
9. Enter your **Bundle ID**: `com.example.myProject`

### Step 3: Test on a real device
**Push notifications do not work on the iOS Simulator.** Use a physical iPhone or iPad.

1. Connect your device and run: `flutter run`
2. Grant notification permission when prompted
3. Create a todo with a time 2–3 minutes in the future
4. Close or background the app
5. Wait for the notification

## Local vs push notifications
- **Local notifications** (`flutter_local_notifications`): Work when the app has been opened at least once after install and can run in the background. No APNs key needed.
- **Push notifications** (FCM): Work when the app is fully closed. Require the APNs key in Firebase.

If local notifications still fail, check:
- Notification permission in **Settings → [Your App] → Notifications**
- You are testing on a **real device**, not the simulator
- The app has been opened at least once after installing
