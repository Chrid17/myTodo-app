import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/todo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final Map<String, Timer> _timers = {};
  static web.HTMLAudioElement? _audio;
  static String? _generatedBeepDataUri;
  
  // In-app notification callback for showing alerts when app is open
  static void Function(String title, String body)? _inAppNotifier;

  static Future<void> initialize() async {
    // Request Notification permission
    await requestPermission();

    // Preload audio asset (if present in assets)
    try {
      final sound = await _resolveSelectedSound();
      final assetPath = sound == null ? null : 'assets/sounds/$sound.mp3';
      if (assetPath != null) {
        _audio = web.HTMLAudioElement()
          ..src = assetPath
          ..preload = 'auto';
      } else {
        _audio = null;
      }
    } catch (e) {
      // Audio preload failed
      _audio = null;
    }
  }
  
  // Request notification permission
  static Future<bool> requestPermission() async {
    try {
      if (!_notificationSupported) return false;
      
      final permission = _getPermissionString();
      if (permission == 'granted') return true;
      if (permission == 'denied') return false;
      
      final result = await web.Notification.requestPermission().toDart;
      return result.toString() == 'granted';
    } catch (e) {
      return false;
    }
  }
  
  // Helper to get permission as a Dart string
  static String _getPermissionString() {
    return web.Notification.permission.toString();
  }
  
  // Check if notifications are enabled
  static bool get isPermissionGranted {
    try {
      return _notificationSupported && _getPermissionString() == 'granted';
    } catch (_) {
      return false;
    }
  }

  static bool get _notificationSupported {
    try {
      return _getPermissionString().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> scheduleNotification(Todo todo) async {
    if (todo.createdAt.isAfter(DateTime.now()) && !todo.isCompleted) {
      final id = todo.id;
      final duration = todo.createdAt.difference(DateTime.now());

      // Cancel existing timers if any (both main and pre)
      await cancelNotification(id);

      // If duration is negative or zero, show immediately
      if (duration.inMilliseconds <= 0) {
        _showNotification(todo);
        return;
      }

      _timers[id] = Timer(duration, () {
        _showNotification(todo);
        _timers.remove(id);
      });

      // Repeat reminders at T+1, T+2, T+3, T+4, T+5 min
      for (int i = 1; i <= 5; i++) {
        final DateTime repeatTime = todo.createdAt.add(Duration(minutes: i));
        final int repeatMs = repeatTime.difference(DateTime.now()).inMilliseconds;
        if (repeatMs > 0) {
          final repeatId = '${id}_repeat_$i';
          _timers[repeatId] = Timer(Duration(milliseconds: repeatMs), () {
            final title = 'Reminder ($i/5): ${todo.title}';
            final body = todo.description.isNotEmpty ? todo.description : 'Don\'t forget this task!';
            try {
              if (_notificationSupported && _getPermissionString() == 'granted') {
                web.Notification(title, web.NotificationOptions(body: body, tag: repeatId));
              }
            } catch (_) {}
            _playAudio();
            if (_inAppNotifier != null) _inAppNotifier!(title, body);
            _timers.remove(repeatId);
          });
        }
      }

      // For high priority, schedule a 5-minute prior reminder
      if (todo.priority == Priority.high) {
        final DateTime preTime = todo.createdAt.subtract(
          const Duration(minutes: 5),
        );
        final int preMs = preTime.difference(DateTime.now()).inMilliseconds;
        if (preMs > 0) {
          final preId = '${id}_pre';
          _timers[preId] = Timer(Duration(milliseconds: preMs), () {
            final title = '⚠️ Due soon: ${todo.title}';
            final body = 'Starting in 5 minutes';
            try {
              if (_notificationSupported &&
                  _getPermissionString() == 'granted') {
                final options = web.NotificationOptions(body: body, tag: preId);
                web.Notification(title, options);
              }
            } catch (_) {}
            
            // Play audio
            _playAudio();
            
            // Show in-app notification
            if (_inAppNotifier != null) {
              _inAppNotifier!(title, body);
            }
          });
        }
      }
    }
  }

  static void _showNotification(Todo todo) {
    final title = '⏰ Todo Reminder: ${todo.title}';
    final body =
        todo.description.isNotEmpty
            ? todo.description
            : 'Time to complete your todo!';

    // Show browser notification
    showBrowserNotification(title, body, todo.id);

    // Try to play the audio (might be blocked by autoplay policies if user hasn't interacted)
    _playAudio();
    
    // Show in-app notification (dialog/snackbar)
    if (_inAppNotifier != null) {
      _inAppNotifier!(title, body);
    }
  }
  
  // Show a browser notification directly
  static void showBrowserNotification(String title, String body, [String? tag]) {
    try {
      if (_notificationSupported && _getPermissionString() == 'granted') {
        final options = web.NotificationOptions(
          body: body, 
          tag: tag ?? 'todo-notification-${DateTime.now().millisecondsSinceEpoch}',
          icon: 'icons/Icon-192.png',
          requireInteraction: true,
        );
        web.Notification(title, options);
      }
    } catch (e) {
      // Failed to show notification
    }
  }
  
  // Show a test notification to verify everything works
  static Future<bool> showTestNotification() async {
    try {
      // First request permission if not granted
      final hasPermission = await requestPermission();
      if (!hasPermission) return false;
      
      // Show test notification
      showBrowserNotification(
        '✅ Notifications Enabled!',
        'You will receive reminders when your tasks are due.',
        'test-notification',
      );
      
      // Play sound
      _playAudio();
      
      return true;
    } catch (e) {
      return false;
    }
  }

  static void _playAudio() {
    try {
      if (_audio != null) {
        _audio!.currentTime = 0;
        _audio!.play();
        return;
      }

      // If no asset audio, try generated beep data URI
      _generatedBeepDataUri ??= _generateBeepDataUri();
      final gen = web.HTMLAudioElement()
        ..src = _generatedBeepDataUri!
        ..preload = 'auto';
      gen.play();
    } catch (e) {
      // Audio play failed
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    _timers.remove(todoId)?.cancel();
    _timers.remove('${todoId}_pre')?.cancel();
    for (int i = 1; i <= 5; i++) {
      _timers.remove('${todoId}_repeat_$i')?.cancel();
    }
  }

  static Future<void> cancelAllNotifications() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  static Future<void> rescheduleNotification(Todo todo) async {
    await cancelNotification(todo.id);
    await scheduleNotification(todo);
  }

  // Play a short test sound (user gesture required by browsers)
  static Future<void> playTestSound() async {
    try {
      if (_audio != null) {
        _audio!.currentTime = 0;
        await _audio!.play().toDart;
        return;
      }

      _generatedBeepDataUri ??= _generateBeepDataUri();
      final gen = web.HTMLAudioElement()
        ..src = _generatedBeepDataUri!
        ..preload = 'auto';
      await gen.play().toDart;
    } catch (e) {
      // playTestSound failed
    }
  }

  // Check if the audio asset exists (returns false if 404)
  static Future<bool> audioAssetExists() async {
    try {
      final sound = await _resolveSelectedSound();
      final path =
          sound == null
              ? 'assets/sounds/notify.mp3'
              : 'assets/sounds/$sound.mp3';
      final response = await web.window.fetch(path.toJS).toDart;
      return response.ok;
    } catch (e) {
      // Request failed (likely 404 or blocked)
      return false;
    }
  }

  // Register a callback for in-app notifications (shows dialog when task is due)
  static void registerInAppNotifier(void Function(String title, String body) fn) {
    _inAppNotifier = fn;
  }

  // Generate a pleasant two-tone chime (no external asset) as a 16-bit PCM WAV data URI.
  // Tone A: 660 Hz (120 ms), short pause (20 ms), Tone B: 880 Hz (140 ms). Applies fade-in/out.
  static String _generateBeepDataUri({int sampleRate = 44100}) {
    const int toneALenMs = 120;
    const int gapMs = 20;
    const int toneBLenMs = 140;
    final int totalMs = toneALenMs + gapMs + toneBLenMs;
    final int numSamples = (sampleRate * totalMs / 1000).round();
    final bytes = ByteData(44 + numSamples * 2);

    // RIFF header
    bytes.setUint8(0, 'R'.codeUnitAt(0));
    bytes.setUint8(1, 'I'.codeUnitAt(0));
    bytes.setUint8(2, 'F'.codeUnitAt(0));
    bytes.setUint8(3, 'F'.codeUnitAt(0));
    bytes.setUint32(4, 36 + numSamples * 2, Endian.little);
    bytes.setUint8(8, 'W'.codeUnitAt(0));
    bytes.setUint8(9, 'A'.codeUnitAt(0));
    bytes.setUint8(10, 'V'.codeUnitAt(0));
    bytes.setUint8(11, 'E'.codeUnitAt(0));

    // fmt chunk
    bytes.setUint8(12, 'f'.codeUnitAt(0));
    bytes.setUint8(13, 'm'.codeUnitAt(0));
    bytes.setUint8(14, 't'.codeUnitAt(0));
    bytes.setUint8(15, ' '.codeUnitAt(0));
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bytes.setUint16(32, 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk header
    bytes.setUint8(36, 'd'.codeUnitAt(0));
    bytes.setUint8(37, 'a'.codeUnitAt(0));
    bytes.setUint8(38, 't'.codeUnitAt(0));
    bytes.setUint8(39, 'a'.codeUnitAt(0));
    bytes.setUint32(40, numSamples * 2, Endian.little);

    int toneASamples = (sampleRate * toneALenMs / 1000).round();
    int gapSamples = (sampleRate * gapMs / 1000).round();
    int toneBSamples = (sampleRate * toneBLenMs / 1000).round();

    for (int i = 0; i < numSamples; i++) {
      double sample = 0.0;
      if (i < toneASamples) {
        // Tone A: 660 Hz with fade in/out
        final t = i / sampleRate;
        final env = _envelope(i, toneASamples);
        sample = env * math.sin(2 * math.pi * 660 * t);
      } else if (i >= toneASamples + gapSamples) {
        // Tone B: 880 Hz with fade in/out
        final i2 = i - (toneASamples + gapSamples);
        final t = i2 / sampleRate;
        final env = _envelope(i2, toneBSamples);
        sample = env * math.sin(2 * math.pi * 880 * t);
      } else {
        sample = 0.0; // gap
      }

      final intInt16 = (32767 * 0.5 * sample).round();
      bytes.setInt16(44 + i * 2, intInt16, Endian.little);
    }

    final uint8 = bytes.buffer.asUint8List();
    final base64Data = base64Encode(uint8);
    return 'data:audio/wav;base64,$base64Data';
  }

  // Simple linear fade-in/out envelope to avoid clicks
  static double _envelope(int index, int total) {
    const int fadeLen = 200; // samples
    final int fadeInEnd = fadeLen;
    final int fadeOutStart = total - fadeLen;
    if (index < 0 || index >= total) return 0.0;
    if (index < fadeInEnd) {
      return index / fadeLen;
    }
    if (index > fadeOutStart) {
      return (total - index) / fadeLen;
    }
    return 1.0;
  }

  // Resolve selected sound from SharedPreferences, same key as mobile.
  static Future<String?> _resolveSelectedSound() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final name = preferences.getString('selected_sound');
      if (name == null || name == 'default') return null;
      return name;
    } catch (_) {
      return null;
    }
  }
}
