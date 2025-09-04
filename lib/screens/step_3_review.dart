// lib/screens/step_3_review.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/verification_service.dart';
import '../service_categories.dart';
import 'verification_progress_screen.dart'; // Added import

class Step3Review extends StatefulWidget {
  final VerificationMode mode;
  final List<String> selectedCategoryIds;
  final PlatformFile? basicId;
  final PlatformFile? basicSelfie;
  final PlatformFile? basicPolice;
  final Map<String, List<PlatformFile>> proofFiles;

  // NEW: whether this user must provide basic docs now (from Step 2)
  final bool needBasicDocs;

  const Step3Review({
    super.key,
    this.mode = VerificationMode.physical,
    this.selectedCategoryIds = const [],
    this.basicId,
    this.basicSelfie,
    this.basicPolice,
    this.proofFiles = const {},
    this.needBasicDocs = true, // default keeps old behavior if not passed
  });

  @override
  State<Step3Review> createState() => _Step3ReviewState();
}

class _Step3ReviewState extends State<Step3Review> {
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final modeStr = widget.mode == VerificationMode.online ? 'online' : 'physical';
    final ids = widget.selectedCategoryIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Review & Submit')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Mode: ${modeStr.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Categories:'),
          const SizedBox(height: 4),
          if (ids.isEmpty)
            const Text('No categories selected.', style: TextStyle(color: Colors.grey))
          else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: ids.map((id) {
                final c = [...kOnlineCategories, ...kPhysicalCategories].firstWhere(
                      (e) => e.id == id,
                  orElse: () => ServiceCategory(id: id, label: id, mode: modeStr),
                );
                return Chip(label: Text(c.label));
              }).toList(),
            ),

          const SizedBox(height: 12),

          // NEW: show basic-docs section only if required now
          if (widget.mode == VerificationMode.physical && widget.needBasicDocs) ...[
            const Text('Basic docs:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _row('NIC/Passport', widget.basicId?.name),
            _row('Selfie', widget.basicSelfie?.name),
            _row('Police clearance', widget.basicPolice?.name),
            const SizedBox(height: 12),
          ],

          const Text('Skill proofs:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final id in ids) _row(id, '${widget.proofFiles[id]?.length ?? 0} file(s)'),

          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ElevatedButton.icon(
            onPressed: _canSubmit(ids) ? _submit : null,
            icon: const Icon(Icons.send),
            label: _submitting ? const Text('Submitting...') : const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // Ellipsize long file names and avoid Row overflow
  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value ?? '—',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  bool _canSubmit(List<String> ids) {
    if (ids.isEmpty) return false;
    final hasProofs = ids.every((id) => (widget.proofFiles[id]?.isNotEmpty ?? false));

    if (widget.mode == VerificationMode.online) return hasProofs;

    // NEW: if basic docs are not required right now (already approved), don't block submit
    if (!widget.needBasicDocs) return hasProofs;

    final basicOk = widget.basicId != null && widget.basicSelfie != null && widget.basicPolice != null;
    return hasProofs && basicOk;
  }

  Future<void> _submit() async {
    final ids = widget.selectedCategoryIds;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final svc = VerificationService();
      final uid = svc.uid;

      // Upload basic docs if provided (physical)
      if (widget.mode == VerificationMode.physical &&
          widget.basicId != null &&
          widget.basicSelfie != null &&
          widget.basicPolice != null) {
        final idRef = await svc.uploadToStorage(
          localPath: widget.basicId!.path!,
          destPath:
          'basic_docs/$uid/id_${DateTime.now().millisecondsSinceEpoch}_${widget.basicId!.name}',
        );
        final selfieRef = await svc.uploadToStorage(
          localPath: widget.basicSelfie!.path!,
          destPath:
          'basic_docs/$uid/selfie_${DateTime.now().millisecondsSinceEpoch}_${widget.basicSelfie!.name}',
        );
        final policeRef = await svc.uploadToStorage(
          localPath: widget.basicPolice!.path!,
          destPath:
          'basic_docs/$uid/police_${DateTime.now().millisecondsSinceEpoch}_${widget.basicPolice!.name}',
        );
        await svc.submitBasicDocs(
            idCard: idRef, selfie: selfieRef, policeClearance: policeRef);
      }

      // Upload proofs per category
      for (final catId in ids) {
        final files = widget.proofFiles[catId] ?? const <PlatformFile>[];
        final uploaded = <FileRef>[];
        for (final f in files) {
          final ref = await svc.uploadToStorage(
            localPath: f.path!,
            destPath:
            'proofs/$uid/${widget.mode == VerificationMode.online ? 'online' : 'physical'}/$catId/${DateTime.now().millisecondsSinceEpoch}_${f.name}',
          );
          uploaded.add(ref);
        }
        await svc.submitCategoryProof(
          categoryId: catId,
          mode: widget.mode,
          files: uploaded,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VerificationProgressScreen(lockBack: true)),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
