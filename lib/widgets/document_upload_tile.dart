
// lib/widgets/document_upload_tile.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

typedef OnFilesPicked = void Function(List<PlatformFile> files);

class DocumentUploadTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool allowMultiple;
  final OnFilesPicked onPicked;
  final List<PlatformFile> initialFiles;

  const DocumentUploadTile({
    super.key,
    required this.title,
    this.subtitle = '',
    this.allowMultiple = true,
    required this.onPicked,
    this.initialFiles = const [],
  });

  @override
  State<DocumentUploadTile> createState() => _DocumentUploadTileState();
}

class _DocumentUploadTileState extends State<DocumentUploadTile> {
  List<PlatformFile> _files = [];

  @override
  void initState() {
    super.initState();
    _files = [...widget.initialFiles];
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: widget.allowMultiple,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );
    if (res != null && mounted) {
      setState(() => _files = res.files);
      widget.onPicked(_files);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: widget.subtitle.isEmpty ? null : Text(widget.subtitle),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Choose files'),
                ),
              ],
            ),
            if (_files.isNotEmpty) const SizedBox(height: 8),
            if (_files.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _files.map((f) {
                  final isImage = (f.extension ?? '').toLowerCase().contains('png') ||
                      (f.extension ?? '').toLowerCase().contains('jpg') ||
                      (f.extension ?? '').toLowerCase().contains('jpeg');
                  return Chip(
                    label: Text(f.name, overflow: TextOverflow.ellipsis),
                    avatar: Icon(isImage ? Icons.image : Icons.picture_as_pdf),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
