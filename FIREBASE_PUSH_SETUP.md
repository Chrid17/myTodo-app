# Firebase Push Notifications Setup Guide

This guide walks you through setting up **Firebase Cloud Messaging (FCM)** for push notifications on **ALL platforms**: Android, iOS, Web, macOS, and Windows.

## Why Firebase?

Your app currently has **local notifications** (work when app is open) and **Web Push** (browsers only). Firebase Cloud Messaging adds **true push notifications** that work when the app is completely closed, on ALL platforms.

---

## Step 1: Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create a project"** (or use an existing one)
3. Enter a project name (e.g., "My Todo App")
4. Enable Google Analytics if desired (optional)
5. Click **Create project**

---

## Step 2: Install FlutterFire CLI

Open your terminal and run:

```bash
# Install the FlutterFire CLI globally
dart pub global activate flutterfire_cli

# Make sure Firebase CLI is also installed
npm install -g firebase-tools

# Login to Firebase
firebase login
```

---

## Step 3: Configure Firebase for Your Flutter App

From your project root directory, run:

```bash
flutterfire configure
```

This will:
- Ask you to select your Firebase project
- Automatically create `lib/firebase_options.dart` with real API keys
- Create `android/app/google-services.json` for Android
- Create `ios/Runner/GoogleService-Info.plist` for iOS
- Configure web settings

**IMPORTANT**: This replaces the placeholder `firebase_options.dart` file.

---

## Step 4: Get the FCM Server Key

1. In Firebase Console, go to **Project Settings** (gear icon)
2. Go to the **Cloud Messaging** tab
3. Under **Cloud Messaging API (Legacy)**, copy the **Server Key**
   - If not enabled, click "Enable" for the Cloud Messaging API
4. Save this key - you'll need it for the Supabase edge function

---

## Step 5: Set Up Supabase Database

Run the SQL migration to create the required tables. In your **Supabase Dashboard > SQL Editor**, paste and run the contents of:

```
supabase/migrations/20260211_device_tokens.sql
```

This creates:
- `device_tokens` table - stores FCM tokens for all platforms
- `scheduled_notifications` table - stores pending notifications

---

## Step 6: Deploy the Supabase Edge Function

**IMPORTANT:** If you ever shared your service account JSON in chat or anywhere public, 
**regenerate it immediately** in Firebase Console > Service accounts > Generate new private key. 
Delete the old one for security.

```bash
# Set the Firebase service account JSON (the entire JSON as one string)
# Get this from Firebase Console > Project Settings > Service accounts > Generate new private key
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"mytodo-app-ce7c2",...}'

# Deploy the edge function
supabase functions deploy send-push-notifications
```

---

## Step 7: Set Up a Cron Job to Send Notifications

Notifications are sent by calling the edge function periodically. Set up a cron job in Supabase:

1. In Supabase Dashboard, go to **Database > Extensions**
2. Enable the **pg_cron** and **pg_net** extensions
3. Go to **SQL Editor** and run:

```sql
-- Send notifications every minute
SELECT cron.schedule(
  'send-push-notifications',
  '* * * * *',
  $$
  SELECT net.http_post(
    url := 'https://pujfapldlclvykjjphjy.supabase.co/functions/v1/send-push-notifications',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1amZhcGxkbGNsdnlrampwaGp5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE2MDMyNzIsImV4cCI6MjA3NzE3OTI3Mn0.OT1S6YpoMT5q_fzuDx21BX0FoRZi8xURK-MBugeuSEU'
    )
  );
  $$
);
```

---

## Step 8: iOS Additional Setup (if targeting iOS)

### Enable Push Notifications in Xcode:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability** and add:
   - **Push Notifications**
   - **Background Modes** (check "Remote notifications" and "Background fetch")

### Upload APNs Key to Firebase:
1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create a new **Key** with **Apple Push Notifications service (APNs)** enabled
3. Download the `.p8` key file
4. In Firebase Console > Project Settings > Cloud Messaging:
   - Under **Apple app configuration**, upload the APNs key
   - Enter the Key ID and Team ID

---

## Step 9: Build and Test

```bash
# Get dependencies
flutter pub get

# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios

# Run on Web
flutter run -d chrome

# Run on Windows
flutter run -d windows
```

### Test notifications:
1. Create a todo with a time 2 minutes in the future
2. Close the app completely
3. Wait for the notification to arrive

---

## How It All Works

### Notification Flow:
```
User creates Todo
     │
     ├─► Local Notification scheduled (flutter_local_notifications)
     │   └─ Works immediately when app is open/background
     │
     ├─► Push Notification saved to Supabase (scheduled_notifications table)
     │   └─ Edge function checks every minute
     │       └─ Sends FCM push to ALL registered devices
     │           ├─ Android (direct FCM)
     │           ├─ iOS (FCM → APNs)
     │           ├─ Web (FCM → browser push)
     │           ├─ macOS (FCM)
     │           └─ Windows (FCM)
     │
     └─► FCM device token saved to Supabase (device_tokens table)
         └─ Refreshed automatically when token changes
```

### Platform Coverage:
| Platform | App Open | App Background | App Closed |
|----------|----------|----------------|------------|
| Android  | Local + FCM | Local (alarm) | FCM Push |
| iOS      | Local + FCM | Local (alarm) | FCM Push (via APNs) |
| Web      | Local (timer) | Web Push | FCM + Web Push |
| Windows  | Local (timer) | - | - |
| macOS    | Local (timer) | FCM Push | FCM Push |

---

## Troubleshooting

### Notifications not showing on Android:
- Check that notification permission is granted in device Settings
- Check that the `todo_reminders` channel is not muted
- On Android 12+, exact alarm permission may need manual approval
- Check: Settings > Apps > Your App > Notifications

### Notifications not showing on iOS:
- Ensure Push Notifications capability is added in Xcode
- Ensure APNs key is uploaded to Firebase
- Check: Settings > Notifications > Your App

### Push notifications not arriving when app is closed:
- Verify the edge function is deployed: `supabase functions list`
- Verify the cron job is running: check `cron.job` table in SQL editor
- Check edge function logs: `supabase functions logs send-push-notifications`
- Verify FCM_SERVER_KEY is set: `supabase secrets list`

### Firebase initialization fails:
- Run `flutterfire configure` again
- Make sure `google-services.json` exists in `android/app/`
- Make sure `GoogleService-Info.plist` exists in `ios/Runner/`
