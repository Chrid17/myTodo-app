import 'package:flutter/material.dart';
import 'package:my_project/ui/pages/todo_list_page.dart';
import 'services/notification_service.dart';
import 'services/todo_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  // Restore scheduled notifications on app launch
  final todos = await TodoService().getTodos();
  for (final t in todos) {
    if (!t.isCompleted && t.createdAt.isAfter(DateTime.now())) {
      await NotificationService.scheduleNotification(t);
    }
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const TodoListPage(),
    );
  }
}
