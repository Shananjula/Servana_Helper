// lib/main.dart — Helper app
// Restores your previous navigation (HomeScreen with bottom nav tabs) and adds
// safe Firebase initialize + FCM token registration for 'helper'.
// No features removed.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Your screens
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

// If you use generated firebase options, import and pass them below.
// import 'firebase_options.dart';

// Push token registration (shared file you already added)
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase safely. Prefer options if you generated them.
  try {
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await Firebase.initializeApp();
  } catch (_) {
    // If both fail, let UI render and show auth gate; errors will appear on use.
  }
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
          return const _HelperHomeWithPush(child: HomeScreen());
        },
      ),

      // Optional: named routes for jumping directly to tabs without replacing root.
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const HomeScreen());
          case '/find': // Find Work tab
            return MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 1));
          case '/jobs': // My Jobs tab
            return MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 2));
          case '/chats': // Chats tab
            return MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 3));
          case '/settings':
          case '/profile': // Profile tab
            return MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 4));
        }
        return null;
      },
    );
  }
}

/// Registers the device FCM token for 'helper' after sign-in,
/// without blocking your existing HomeScreen UI.
class _HelperHomeWithPush extends StatefulWidget {
  final Widget child;
  const _HelperHomeWithPush({required this.child});

  @override
  State<_HelperHomeWithPush> createState() => _HelperHomeWithPushState();
}

class _HelperHomeWithPushState extends State<_HelperHomeWithPush> {
  @override
  void initState() {
    super.initState();
    _initPush();
  }

  Future<void> _initPush() async {
    try {
      await PushService.instance.initForCurrentUser(appRole: 'helper');
    } catch (_) {
      // Never block UI on push setup
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
