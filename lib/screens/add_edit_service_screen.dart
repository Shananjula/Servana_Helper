// lib/screens/add_edit_service_screen.dart
//
// Add/Edit Service (Helper app, Phase 0)
// --------------------------------------
// • Create or update a service document in /services
// • Fields: title, category, price (LKR), description, isActive, image (optional)
// • When creating: sets helperId and createdAt
// • When editing: loads existing values; updates updatedAt
//
// Firestore shape (tolerant):
//   services/{serviceId} {
//     helperId: string,
//     title: string,
//     category?: string,
//     price?: number,
//     description?: string,
//     isActive?: bool,
//     imageUrl?: string,
//     createdAt?: Timestamp,
//     updatedAt?: Timestamp
//   }
//
// Deps: cloud_firestore, firebase_auth, firebase_storage, image_picker, flutter/material.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AddEditServiceScreen extends StatefulWidget {
  const AddEditServiceScreen({super.key, this.serviceId});

  final String? serviceId;

  @override
  State<AddEditServiceScreen> createState() => _AddEditServiceScreenState();
}

class _AddEditServiceScreenState extends State<AddEditServiceScreen> {
  // Categories you already use elsewhere; adjust as needed
  static const List<String> _kCategories = <String>[
    'Cleaning', 'Delivery', 'Repairs', 'Tutoring', 'Design', 'Writing',
  ];

  final _form = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  String? _category;
  bool _active = true;

  String? _imageUrl;   // existing remote image
  XFile? _picked;      // new local pick

  bool _loading = true;
  bool _saving  = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _prime() async {
    try {
      if (widget.serviceId == null) {
        setState(() => _loading = false);
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('services').doc(widget.serviceId).get();
      final m = doc.data() ?? {};
      _titleCtrl.text = (m['title'] ?? '').toString();
      _category = (m['category'] ?? '').toString().isEmpty ? null : (m['category'] as String);
      final price = m['price'];
      if (price is num) _priceCtrl.text = price.toStringAsFixed(0);
      _descCtrl.text = (m['description'] ?? '').toString();
      _active = m['isActive'] != false;
      _imageUrl = (m['imageUrl'] ?? '').toString().isEmpty ? null : (m['imageUrl'] as String);
    } catch (_) {
      // keep defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (x != null && mounted) setState(() => _picked = x);
    } catch (_) {}
  }

  Future<String?> _uploadPicked(String docId) async {
    if (_picked == null) return _imageUrl; // nothing to upload
    try {
      final ref = FirebaseStorage.instance
          .ref('services/$docId/${DateTime.now().millisecondsSinceEpoch}_${_picked!.name}');
      await ref.putFile(File(_picked!.path));
      return await ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e'), backgroundColor: Colors.red),
        );
      }
      return _imageUrl; // keep old if upload failed
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_form.currentState?.validate() ?? false)) return;

    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final col = FirebaseFirestore.instance.collection('services');
      DocumentReference<Map<String, dynamic>> ref;

      if (widget.serviceId == null) {
        ref = col.doc(); // create
      } else {
        ref = col.doc(widget.serviceId);
      }

      // If this is a new service and image was picked, we still need an id to upload under.
      final docId = ref.id;
      final imageUrl = await _uploadPicked(docId);

      final price = num.tryParse(_priceCtrl.text.trim());

      final payload = <String, dynamic>{
        'helperId': uid,
        'title': _titleCtrl.text.trim(),
        'category': _category,
        if (price != null) 'price': price,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'isActive': _active,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.serviceId == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await ref.set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service saved.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceId == null ? 'Add service' : 'Edit service'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('SAVE'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            // Title
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g., Apartment deep cleaning'),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Please enter at least 3 characters' : null,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Category + Price
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: _kCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v),
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Price (LKR)', hintText: 'e.g., 2500'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Description
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: TextFormField(
                  controller: _descCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Briefly describe what’s included, materials, timing, etc.',
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Active + Image
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                      title: const Text('Active'),
                      subtitle: const Text('Show this service to posters'),
                      secondary: const Icon(Icons.visibility_rounded),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _picked != null
                          ? CircleAvatar(backgroundImage: FileImage(File(_picked!.path)))
                          : (_imageUrl != null
                          ? CircleAvatar(backgroundImage: NetworkImage(_imageUrl!))
                          : CircleAvatar(
                        backgroundColor: cs.primary.withOpacity(0.12),
                        foregroundColor: cs.primary,
                        child: const Icon(Icons.photo_library_rounded),
                      )),
                      title: const Text('Image (optional)'),
                      subtitle: Text(_picked != null
                          ? 'Selected'
                          : (_imageUrl != null ? 'Current image' : 'Add a representative photo')),
                      trailing: FilledButton.tonal(
                        onPressed: _pickImage,
                        child: const Text('Choose'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
