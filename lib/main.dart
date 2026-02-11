import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:my_project/ui/pages/todo_list_page.dart';
import 'services/notification_service.dart';
import 'services/todo_service.dart';
import 'services/share_utils.dart';
import 'services/supabase_client.dart';
import 'services/supabase_todo_service.dart';
import 'models/todo.dart';

// Firebase imports (push notifications for all platforms)
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize local notifications (works immediately, no setup needed)
  await NotificationService.initialize();

  // 2. Initialize Firebase for push notifications (cross-platform)
  //    This will fail gracefully if Firebase is not yet configured.
  //    Local notifications will still work without Firebase.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    debugPrint('Firebase: Initialized successfully');
  } catch (e) {
    debugPrint(
      'Firebase: Not configured yet - push notifications disabled. '
      'Run "flutterfire configure" to enable. Error: $e',
    );
  }

  // 3. Initialize Supabase
  const supabaseUrl = 'https://pujfapldlclvykjjphjy.supabase.co';
  const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1amZhcGxkbGNsdnlrampwaGp5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE2MDMyNzIsImV4cCI6MjA3NzE3OTI3Mn0.OT1S6YpoMT5q_fzuDx21BX0FoRZi8xURK-MBugeuSEU';
  await AppSupabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await AppSupabase.ensureAnonSignIn();

  // 4. Initialize FCM push notifications (after Firebase + Supabase are ready)
  if (firebaseReady) {
    try {
      await FcmService.initialize();
      // Subscribe to a global topic so all devices receive broadcast notifications
      await FcmService.subscribeToTopic('all_users');
      debugPrint(
        'FCM: Push notifications active. Token: ${FcmService.currentToken}',
      );
    } catch (e) {
      debugPrint('FCM: Initialization failed: $e');
    }
  }

  // 5. Restore scheduled local notifications from local cache
  final localTodos = await TodoService().getTodos();
  for (final t in localTodos) {
    if (!t.isCompleted && t.createdAt.isAfter(DateTime.now())) {
      await NotificationService.scheduleNotification(t);
    }
  }

  // 6. Also schedule upcoming tasks from Supabase on launch
  try {
    final remoteTodos = await SupabaseTodoService().getTodos();
    for (final t in remoteTodos) {
      if (!t.isCompleted && t.createdAt.isAfter(DateTime.now())) {
        await NotificationService.scheduleNotification(t);
      }
    }
  } catch (_) {}

  // 7. Parse shared data from URL on web
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
      home: TodoListPage(
        readOnly: sharedTodos != null,
        sharedTodos: sharedTodos,
      ),
    );
  }
}
