// lib/screens/step_1_services.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/verification_service.dart';
import 'step_2_documents.dart';
import '../service_categories.dart';

class Step1Services extends StatefulWidget {
  final VerificationMode mode;
  const Step1Services({super.key, required this.mode});

  @override
  State<Step1Services> createState() => _Step1ServicesState();
}

class _Step1ServicesState extends State<Step1Services> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final modeStr =
    widget.mode == VerificationMode.online ? 'online' : 'physical';
    final items = allCategoriesForMode(modeStr);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in')));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final user = snap.data?.data() as Map<String, dynamic>?;
        final allowed = (user?['allowedCategoryIds'] is List)
            ? Set<String>.from(user!['allowedCategoryIds'])
            : <String>{};

        // Filter out verified ones from the payload we pass to Step 2
        final unverifiedSelection =
        _selected.where((id) => !allowed.contains(id)).toList();

        return Scaffold(
          appBar: AppBar(title: Text('Select ${modeStr.toUpperCase()} categories')),
          body: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    final isVerified = allowed.contains(c.id);
                    final isChecked = _selected.contains(c.id);

                    return ListTile(
                      enabled: !isVerified, // prevent re-submitting verified
                      title: Text(c.label),
                      subtitle: isVerified
                          ? const Text('Verified', style: TextStyle(color: Colors.green))
                          : null,
                      trailing: isVerified
                          ? const Chip(
                        label: Text('Verified'),
                        backgroundColor: Color(0x1A00A86B), // green tint
                        labelStyle: TextStyle(color: Color(0xFF00A86B)),
                      )
                          : Checkbox(
                        value: isChecked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(c.id);
                            } else {
                              _selected.remove(c.id);
                            }
                          });
                        },
                      ),
                      onTap: isVerified
                          ? null
                          : () {
                        setState(() {
                          if (isChecked) {
                            _selected.remove(c.id);
                          } else {
                            _selected.add(c.id);
                          }
                        });
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemCount: items.length,
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: unverifiedSelection.isEmpty
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Step2Documents(
                            mode: widget.mode,
                            selectedCategoryIds: unverifiedSelection,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.navigate_next),
                    label: Text('Next (${unverifiedSelection.length} selected)'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
