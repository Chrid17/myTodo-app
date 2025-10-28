import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:html' as html;
import '../models/todo.dart';

class NotificationService {
  static final Map<String, Timer> _timers = {};
  static html.AudioElement? _audio;
  static String? _generatedBeepDataUri;

  static Future<void> initialize() async {
    // Request Notification permission
    try {
      if (html.Notification.supported) {
        if (html.Notification.permission != 'granted') {
          await html.Notification.requestPermission();
        }
      }
    } catch (e) {
      print('Notification permission request failed: $e');
    }

    // Preload audio asset (if present in assets)
    try {
      _audio = html.AudioElement('assets/sounds/notify.mp3')..preload = 'auto';
    } catch (e) {
      print('Audio preload failed: $e');
      _audio = null;
    }
  }

  static Future<void> scheduleNotification(Todo todo) async {
    if (todo.createdAt.isAfter(DateTime.now()) && !todo.isCompleted) {
      final id = todo.id;
      final duration = todo.createdAt.difference(DateTime.now());

      // Cancel existing timer if any
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
    }
  }

  static void _showNotification(Todo todo) {
    final title = 'Todo Reminder: ${todo.title}';
    final body =
        todo.description.isNotEmpty
            ? todo.description
            : 'Time to complete your todo!';

    try {
      if (html.Notification.supported &&
          html.Notification.permission == 'granted') {
        // Show browser notification
        html.Notification(title, body: body, tag: todo.id);
      } else {
        // Fallback: log or show an in-app alert
        print('Notification not permitted or supported.');
      }
    } catch (e) {
      print('Failed to show notification: $e');
    }

    // Try to play the audio (might be blocked by autoplay policies if user hasn't interacted)
    try {
      if (_audio != null) {
        _audio!.currentTime = 0;
        _audio!.play();
        return;
      }

      // If no asset audio, try generated beep data URI
      if (_generatedBeepDataUri == null) {
        _generatedBeepDataUri = _generateBeepDataUri();
      }
      final gen = html.AudioElement(_generatedBeepDataUri!)..preload = 'auto';
      gen.play();
    } catch (e) {
      print('Audio play failed: $e');
    }
  }

  static Future<void> cancelNotification(String todoId) async {
    final timer = _timers.remove(todoId);
    timer?.cancel();
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
        await _audio!.play();
        return;
      }

      if (_generatedBeepDataUri == null) {
        _generatedBeepDataUri = _generateBeepDataUri();
      }
      final gen = html.AudioElement(_generatedBeepDataUri!)..preload = 'auto';
      await gen.play();
    } catch (e) {
      print('playTestSound failed: $e');
    }
  }

  // Check if the audio asset exists (returns false if 404)
  static Future<bool> audioAssetExists() async {
    try {
      final request = await html.HttpRequest.request(
        'assets/sounds/notify.mp3',
        method: 'GET',
      );
      return request.status == 200;
    } catch (e) {
      // Request failed (likely 404 or blocked)
      return false;
    }
  }

  // Generate a short 16-bit PCM WAV data URI (sine beep) so web can play without an asset
  static String _generateBeepDataUri({
    int freq = 880,
    int durationMs = 250,
    int sampleRate = 44100,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
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
    bytes.setUint32(16, 16, Endian.little); // subchunk1 size
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

    // Fill samples
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final sample = (32767 * 0.5 * (math.sin(2 * math.pi * freq * t))).round();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }

    final uint8 = bytes.buffer.asUint8List();
    final base64Data = base64Encode(uint8);
    return 'data:audio/wav;base64,$base64Data';
  }
}
