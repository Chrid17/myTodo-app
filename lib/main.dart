import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:my_project/ui/pages/todo_list_page.dart';
import 'services/notification_service.dart';
import 'services/todo_service.dart';
import 'services/share_utils.dart';
import 'services/supabase_client.dart';
import 'services/supabase_todo_service.dart';
import 'models/todo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();

  // Initialize Supabase (insert your project URL and anon key)
  const supabaseUrl = 'https://pujfapldlclvykjjphjy.supabase.co';
  const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1amZhcGxkbGNsdnlrampwaGp5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE2MDMyNzIsImV4cCI6MjA3NzE3OTI3Mn0.OT1S6YpoMT5q_fzuDx21BX0FoRZi8xURK-MBugeuSEU';
  await AppSupabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await AppSupabase.ensureAnonSignIn();

  // Restore scheduled notifications from local cache (legacy)
  final localTodos = await TodoService().getTodos();
  for (final t in localTodos) {
    if (!t.isCompleted && t.createdAt.isAfter(DateTime.now())) {
      await NotificationService.scheduleNotification(t);
    }
  }

  // Also schedule upcoming tasks from Supabase on launch
  try {
    final remoteTodos = await SupabaseTodoService().getTodos();
    for (final t in remoteTodos) {
      if (!t.isCompleted && t.createdAt.isAfter(DateTime.now())) {
        await NotificationService.scheduleNotification(t);
      }
    }
  } catch (_) {}

  // Parse shared data from URL on web
  List<Todo>? sharedTodos;
  if (kIsWeb) {
    try {
      final uri = Uri.base;
      final dataParam = uri.queryParameters['data'];
      if (dataParam != null && dataParam.isNotEmpty) {
        sharedTodos = ShareUtils.decodeTodos(dataParam);
      }
    } catch (_) {}
  }

  runApp(MyApp(sharedTodos: sharedTodos));
}

class MyApp extends StatelessWidget {
  final List<Todo>? sharedTodos;
  const MyApp({super.key, this.sharedTodos});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todo App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: TodoListPage(readOnly: sharedTodos != null, sharedTodos: sharedTodos),
    );
  }
}
