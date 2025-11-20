# Notification Sound Setup

## Current Configuration

The app is configured to use **pleasant system notification sounds** that work across all platforms:

### Platform-Specific Sounds:

1. **Android**: Uses the default system notification sound (already pleasant)
2. **iOS**: Uses the default system notification sound  
3. **Windows**: Uses the default system notification sound
4. **Web**: Uses browser notification API (system sound)

### Why System Sounds?

- ✅ **Cross-platform compatibility**: Works on all devices
- ✅ **User familiarity**: Users are accustomed to their system sounds
- ✅ **Accessibility**: Respects user's sound preferences
- ✅ **No extra files needed**: No need to bundle custom audio files
- ✅ **Professional**: System sounds are already well-designed

## Custom Sound (Optional)

If you want to add a custom notification sound in the future:

### For Android:
1. Add your sound file (e.g., `notification.mp3`) to `android/app/src/main/res/raw/`
2. Update the notification service to reference it

### For iOS:
1. Add your sound file (e.g., `notification.wav`) to the iOS project
2. Ensure it's added to the bundle resources
3. Update the notification service to reference it

### For Web:
- Web notifications use browser's default sound (cannot be customized for security reasons)

## Current Implementation

The notification service is configured with:
- **High importance** for urgent notifications
- **Sound enabled** by default
- **Priority-based interruption levels** (iOS 15+)
- **Vibration** on supported devices

All notifications will play a pleasant sound that matches the user's system preferences.
