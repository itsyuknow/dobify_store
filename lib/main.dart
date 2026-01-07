import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_options.dart';
import 'theme.dart';
import 'pages/login_page.dart';
import 'pages/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseOptions.supabaseUrl,
    anonKey: SupabaseOptions.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );

  runApp(const DobifyStoreApp());
}

class DobifyStoreApp extends StatelessWidget {
  const DobifyStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dobify Store',
      debugShowCheckedModeBanner: false,
      theme: dobifyTheme,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    // FIX 1: Provide initialIndex
    if (session != null) {
      return const HomeShell(initialIndex: 0);
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final event = snapshot.data?.event;

        if (event == AuthChangeEvent.signedIn ||
            Supabase.instance.client.auth.currentSession != null) {
          // FIX 2: Provide initialIndex
          return const HomeShell(initialIndex: 0);
        }

        return const LoginPage();
      },
    );
  }
}
