// lib/screens/step_2_documents.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../services/verification_service.dart';
import '../widgets/document_upload_tile.dart';
import '../service_categories.dart';
import 'step_3_review.dart';

class Step2Documents extends StatefulWidget {
  // Defaults allow old calls like `const Step2Documents()` to compile.
  final VerificationMode mode;
  final List<String> selectedCategoryIds;
  final String? initialCategoryId; // legacy param some screens use

  const Step2Documents({
    super.key,
    this.mode = VerificationMode.physical,
    this.selectedCategoryIds = const [],
    this.initialCategoryId,
  });

  @override
  State<Step2Documents> createState() => _Step2DocumentsState();
}

class _Step2DocumentsState extends State<Step2Documents> {
  final Map<String, List<PlatformFile>> _proofFiles = {}; // per category
  PlatformFile? _idCard, _selfie, _police;
  bool _needBasicDocs = false; // Only for physical first time
  bool _loading = true;

  List<String> get _effectiveCategoryIds {
    if (widget.selectedCategoryIds.isNotEmpty) return widget.selectedCategoryIds;
    if (widget.initialCategoryId != null &&
        widget.initialCategoryId!.trim().isNotEmpty) {
      return [widget.initialCategoryId!.trim()];
    }
    return const <String>[];
  }

  @override
  void initState() {
    super.initState();
    _checkBasicDocs();
  }

  Future<void> _checkBasicDocs() async {
    if (widget.mode == VerificationMode.online) {
      setState(() { _needBasicDocs = false; _loading = false; });
      return;
    }
    final service = VerificationService();
    try {
      final docs = await service.getBasicDocsOnce();
      final need = (docs == null) || (docs.status != 'approved');
      setState(() { _needBasicDocs = need; _loading = false; });
    } catch (e) {
      // If rules or App Check block the read, don’t crash — just ask for basic docs.
      setState(() { _needBasicDocs = true; _loading = false; });
    }
  }

  Future<void> _pickSingleBasic(void Function(PlatformFile) set) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (res != null && res.files.isNotEmpty) {
      set(res.files.first);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final ids = _effectiveCategoryIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload documents')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_needBasicDocs) ...[
            const Text('Basic documents (Physical – one-time)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _BasicPicker(
              title: 'National ID (NIC/Passport)',
              onTap: () => _pickSingleBasic((f) => _idCard = f),
              file: _idCard,
            ),
            _BasicPicker(
              title: 'Selfie (face clear)',
              onTap: () => _pickSingleBasic((f) => _selfie = f),
              file: _selfie,
            ),
            _BasicPicker(
              title: 'Police clearance (PDF or photo)',
              onTap: () => _pickSingleBasic((f) => _police = f),
              file: _police,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
          ],
          const Text('Skill proofs per category',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (ids.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No categories selected yet.\nUse the previous step to pick categories, or pass initialCategoryId.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          for (final id in ids) ...[
            _ProofSection(
              categoryId: id,
              onPicked: (files) {
                _proofFiles[id] = files;
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _canContinue(ids)
                ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Step3Review(
                    mode: widget.mode,
                    selectedCategoryIds: ids,
                    basicId: _idCard,
                    basicSelfie: _selfie,
                    basicPolice: _police,
                    proofFiles: _proofFiles,
                    needBasicDocs: _needBasicDocs, // NEW: tell Step 3 whether basics are required
                  ),
                ),
              );
            }
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Review & Submit'),
          ),
        ],
      ),
    );
  }

  bool _canContinue(List<String> ids) {
    final hasProofs =
        ids.isNotEmpty && ids.every((id) => (_proofFiles[id]?.isNotEmpty ?? false));
    if (widget.mode == VerificationMode.online) return hasProofs;
    if (!_needBasicDocs) return hasProofs;
    return hasProofs && _idCard != null && _selfie != null && _police != null;
  }
}

class _ProofSection extends StatelessWidget {
  final String categoryId;
  final void Function(List<PlatformFile>) onPicked;
  const _ProofSection({required this.categoryId, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final all = [...kOnlineCategories, ...kPhysicalCategories];
    final cat = all.firstWhere(
          (c) => c.id == categoryId,
      orElse: () => ServiceCategory(id: categoryId, label: categoryId, mode: 'online'),
    );
    return DocumentUploadTile(
      title: cat.label,
      subtitle: 'Upload samples: images or PDFs. At least one file.',
      onPicked: onPicked,
      allowMultiple: true,
    );
  }
}

class _BasicPicker extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final PlatformFile? file;
  const _BasicPicker({required this.title, required this.onTap, required this.file});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: file == null
          ? const Text('Not selected')
          : Text(file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.upload_file),
        label: const Text('Choose'),
      ),
    );
  }
}
