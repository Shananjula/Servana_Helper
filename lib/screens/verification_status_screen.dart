
// lib/screens/verification_status_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/verification_service.dart';

class VerificationStatusScreen extends StatelessWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Basic Docs (for Physical)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('basic_docs').doc(uid).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Text('No basic docs submitted yet.');
              if (!snap.data!.exists) return const Text('No basic docs submitted yet.');
              final m = snap.data!.data() as Map<String, dynamic>;
              final status = (m['status'] ?? 'pending') as String;
              final notes = m['notes'] as String?;
              return _Tile(title: 'Basic documents', status: status, notes: notes);
            },
          ),
          const Divider(height: 32),
          const Text('Category Proofs', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('category_proofs').where('userId', isEqualTo: uid).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('No category proofs submitted yet.');
              return Column(
                children: docs.map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final status = (m['status'] ?? 'pending') as String;
                  final notes = m['notes'] as String?;
                  final mode = m['mode'] ?? 'online';
                  final catId = m['categoryId'] ?? '—';
                  return _Tile(title: '$catId  •  $mode', status: status, notes: notes);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final String status;
  final String? notes;
  const _Tile({required this.title, required this.status, this.notes});

  Color _colorFor(String s, BuildContext context) {
    switch (s) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'needs_more_info': return Colors.orange;
      default: return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: notes == null ? null : Text(notes!),
        trailing: Chip(label: Text(status), backgroundColor: _colorFor(status, context).withOpacity(0.15)),
      ),
    );
  }
}
