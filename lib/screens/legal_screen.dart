// lib/screens/legal_screen.dart
//
// Minimal Legal & Privacy screen (Helper app)
// Safe placeholder until you wire real content or a webview.

import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.title = 'Legal & Privacy'});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            'Your terms of service and privacy policy go here.\n\n'
                '• Data we collect\n'
                '• How we use it\n'
                '• Your rights\n'
                '• Contact & support\n\n'
                'Replace this placeholder with your real content or a WebView.',
          ),
        ),
      ),
    );
  }
}
