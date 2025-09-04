// lib/screens/edit_profile_screen.dart
//
// Edit Profile (both roles)
// • Avatar (upload), Display name, Bio
// • Languages (comma-separated → stored as [String])
// • Work location address (text; map picker lives elsewhere if you want coords)
// • Optional hourly rate (visible for helpers)
// • Portfolio images: add/remove (stores URLs in users/{uid}.portfolioImageUrls)
// • Saves to users/{uid} with merge, friendly to missing fields
//
// Safe fallbacks:
// • If user is not signed in, shows a simple message
// • If Storage upload fails, shows a toast and keeps local state intact
//
// Notes:
// • We update Firestore’s photoURL; if you also mirror to FirebaseAuth user,
//   you can add FirebaseAuth.instance.currentUser?.updatePhotoURL(url) after upload.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/screens/verification_center_screen.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _langsCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _avatarUrl;
  XFile? _pickedAvatar;

  final List<String> _portfolio = <String>[];
  final List<XFile> _pickedPortfolio = <XFile>[];

  bool _isHelper = false;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _langsCtrl.dispose();
    _addrCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _prime() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final m = snap.data() ?? {};
      _nameCtrl.text = (m['displayName'] ?? '') as String;
      _bioCtrl.text = (m['bio'] ?? '') as String;
      _langsCtrl.text = ((m['languages'] as List?)?.cast<String>() ?? const <String>[]).join(', ');
      _addrCtrl.text = (m['workLocationAddress'] ?? '') as String;
      _avatarUrl = (m['photoURL'] ?? '') as String?;
      _isHelper = (m['role'] ?? 'poster') == 'helper' || (m['isHelper'] == true);
      final rate = (m['hourlyRate'] is num) ? (m['hourlyRate'] as num).toDouble() : null;
      if (rate != null) _rateCtrl.text = rate.toStringAsFixed(0);

      final port = (m['portfolioImageUrls'] as List?)?.cast<String>() ?? const <String>[];
      _portfolio
        ..clear()
        ..addAll(port);

      setState(() => _loading = false);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
      if (x != null) setState(() => _pickedAvatar = x);
    } catch (_) {}
  }

  Future<void> _pickPortfolio() async {
    try {
      final xs = await ImagePicker().pickMultiImage(imageQuality: 82);
      if (xs.isNotEmpty) {
        setState(() => _pickedPortfolio.addAll(xs));
      }
    } catch (_) {}
  }

  Future<String?> _uploadOne(XFile x, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref('$path/${DateTime.now().millisecondsSinceEpoch}_${x.name}');
      await ref.putFile(File(x.path));
      return await ref.getDownloadURL();
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      // 1) Upload avatar if picked
      String? newAvatarUrl = _avatarUrl;
      if (_pickedAvatar != null) {
        final url = await _uploadOne(_pickedAvatar!, 'users/$uid/avatar');
        if (url != null) newAvatarUrl = url;
      }

      // 2) Upload any newly picked portfolio images
      final newPortfolioUrls = <String>[];
      for (final x in _pickedPortfolio) {
        final url = await _uploadOne(x, 'users/$uid/portfolio');
        if (url != null) newPortfolioUrls.add(url);
      }

      // 3) Build patch
      final langs = _langsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final patch = <String, dynamic>{
        'displayName': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'languages': langs,
        'workLocationAddress': _addrCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final rate = num.tryParse(_rateCtrl.text.trim());
      if (_isHelper && rate != null && rate > 0) {
        patch['hourlyRate'] = rate;
      }
      if (newAvatarUrl != null && newAvatarUrl.isNotEmpty) {
        patch['photoURL'] = newAvatarUrl;
      }
      if (newPortfolioUrls.isNotEmpty) {
        patch['portfolioImageUrls'] = FieldValue.arrayUnion(newPortfolioUrls);
      }

      // 4) Write Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set(patch, SetOptions(merge: true));

      // Clear local picks that were uploaded
      setState(() {
        if (newAvatarUrl != null) _avatarUrl = newAvatarUrl;
        _pickedAvatar = null;
        _portfolio.addAll(newPortfolioUrls);
        _pickedPortfolio.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePortfolio(String url) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'portfolioImageUrls': FieldValue.arrayRemove([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _portfolio.remove(url));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from portfolio.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not remove: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in to edit your profile.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          // Avatar + name
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: _pickedAvatar != null
                            ? FileImage(File(_pickedAvatar!.path))
                            : (_avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? NetworkImage(_avatarUrl!)
                            : null) as ImageProvider<Object>?,
                        child: (_avatarUrl == null || _avatarUrl!.isEmpty) && _pickedAvatar == null
                            ? const Icon(Icons.person, size: 36)
                            : null,
                      ),
                      Positioned(
                        right: -6,
                        bottom: -4,
                        child: IconButton.filledTonal(
                          onPressed: _pickAvatar,
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          tooltip: 'Change photo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Display name'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Helper verification hint
          if (_isHelper)
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final m = snap.data!.data() ?? const <String, dynamic>{};
                final allowed = (m['allowedCategoryIds'] is List) ? List<String>.from(m['allowedCategoryIds']) : const <String>[];
                if (allowed.isNotEmpty) return const SizedBox.shrink();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Upload your verification documents',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          'Physical: basic docs + category proof • Online: category proof only',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VerificationCenterScreen(),
                                ),
                              ),
                              child: const Text('Open center'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const step2.Step2Documents(),
                                ),
                              ),
                              child: const Text('Open documents'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 12),

          // Bio
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About you', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bioCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Tell people about your skills and experience…',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Languages + Address
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Languages (comma-separated)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _langsCtrl,
                    decoration: const InputDecoration(hintText: 'English, Sinhala, Tamil'),
                  ),
                  const SizedBox(height: 12),
                  Text('Work location address', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addrCtrl,
                    decoration: const InputDecoration(hintText: 'No. 123, Street, City'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Hourly rate (helpers)
          if (_isHelper)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: TextField(
                  controller: _rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Hourly rate (LKR)',
                    hintText: 'e.g., 2500',
                  ),
                ),
              ),
            ),

          if (_isHelper) const SizedBox(height: 12),

          // Portfolio
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Portfolio images', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_portfolio.isEmpty && _pickedPortfolio.isEmpty)
                    const Text('No images yet. Add photos of your work.')
                  else
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _portfolio.length + _pickedPortfolio.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final isNew = i >= _portfolio.length;
                          if (isNew) {
                            final x = _pickedPortfolio[i - _portfolio.length];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(File(x.path), height: 110, width: 150, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: IconButton.filledTonal(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(() => _pickedPortfolio.removeAt(i - _portfolio.length)),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            final url = _portfolio[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(url, height: 110, width: 150, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: IconButton.filledTonal(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _removePortfolio(url),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _pickPortfolio,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Add photos'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Tip: Use clear, well-lit photos. Avoid showing personal information.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
          ),
        ),
      ),
    );
  }
}
