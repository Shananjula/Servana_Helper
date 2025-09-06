// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

// If you use generated firebase options, import them here, e.g.:
// import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    // If you're using generated options, uncomment and pass them:
    // options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ServanaHelperApp());
}

class ServanaHelperApp extends StatelessWidget {
  const ServanaHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Servana Helper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      // We don’t rely on initialRoute; we compute the home below via auth state.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          // Splash while Firebase connects
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = snap.data;
          if (user == null) {
            // Not signed in → go to your login/onboarding flow
            return const LoginScreen();
          }

          // Signed in → ALWAYS go through HomeScreen so bottom nav is present
          return const HomeScreen();
        },
      ),

      // Optional: allow named routes to jump directly to a specific tab
      // without replacing the root with a leaf page.
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const HomeScreen());
          case '/find': // Find Work tab
            return MaterialPageRoute(
              builder: (_) => const HomeScreen(initialIndex: 1),
            );
          case '/jobs': // My Jobs tab
            return MaterialPageRoute(
              builder: (_) => const HomeScreen(initialIndex: 2),
            );
          case '/chats': // Chats tab
            return MaterialPageRoute(
              builder: (_) => const HomeScreen(initialIndex: 3),
            );
          case '/settings':
          case '/profile': // Profile tab
            return MaterialPageRoute(
              builder: (_) => const HomeScreen(initialIndex: 4),
            );
        }
        return null;
      },
    );
  }
}
cd