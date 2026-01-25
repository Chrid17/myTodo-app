import 'dart:convert';

import '../models/todo.dart';

/// Utilities to encode/decode todo lists into a URL-safe string for sharing
/// without using any backend or database.
class ShareUtils {
  /// Encode a list of todos into a base64url string (no compression to remain
  /// compatible with web without extra packages).
  static String encodeTodos(List<Todo> todos) {
    final listJson = todos.map((t) => t.toJson()).toList();
    final jsonStr = jsonEncode({
      'v': 1,
      'todos': listJson,
    });
    final b64 = base64Url.encode(utf8.encode(jsonStr));
    return b64;
  }

  /// Decode a base64url string into a list of todos. Returns empty list on error.
  static List<Todo> decodeTodos(String data) {
    try {
      final jsonStr = utf8.decode(base64Url.decode(data));
      final obj = jsonDecode(jsonStr);
      final raw = (obj is Map && obj['todos'] is List) ? (obj['todos'] as List) : <dynamic>[];
      return raw
          .map((e) => Todo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Build a shareable URL pointing to the current origin/path with a single
  /// `data` query parameter that contains the encoded todos.
  static String buildShareUrl(Uri currentBase, List<Todo> todos) {
    final data = encodeTodos(todos);
    final newUri = Uri(
      scheme: currentBase.scheme,
      host: currentBase.host,
      port: currentBase.hasPort ? currentBase.port : null,
      path: currentBase.path.isEmpty ? '/' : currentBase.path,
      queryParameters: {'data': data},
    );
    return newUri.toString();
  }
}
