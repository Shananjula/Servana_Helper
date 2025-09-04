
// lib/widgets/proof_photo_picker.dart
// Minimal wrapper to collect photo evidence. Uses file_picker to keep deps light.
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class ProofPhotoPicker extends StatelessWidget {
  final String label;
  final void Function(List<PlatformFile>) onPicked;
  const ProofPhotoPicker({super.key, required this.label, required this.onPicked});

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (res != null) onPicked(res.files);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _pick,
      icon: const Icon(Icons.add_a_photo),
      label: Text(label),
    );
  }
}
