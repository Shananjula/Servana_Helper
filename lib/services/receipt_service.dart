// lib/services/receipt_service.dart
// Generate & share a simple PDF receipt for a completed task.

import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptService {
  static Future<void> shareTaskReceipt({
    required Map<String, dynamic> task,
    String? helperName,
    String? posterName,
  }) async {
    final pdf = await _build(task: task, helperName: helperName, posterName: posterName);
    await Printing.sharePdf(bytes: pdf, filename: 'servana_receipt_${task['id'] ?? ''}.pdf');
  }

  static Future<Uint8List> _build({
    required Map<String, dynamic> task,
    String? helperName,
    String? posterName,
  }) async {
    final doc = pw.Document();
    final nf = NumberFormat('#,##0');

    int _toInt(dynamic v) => (v is num) ? v.round() : 0;

    final title = (task['title'] ?? 'Task') as String;
    final taskId = (task['id'] ?? '') as String;
    final cat = (task['category'] ?? '') as String;
    final type = (task['type'] ?? '') as String;
    final address = (task['address'] ?? '') as String;

    final base = _toInt(task['finalAmount'] ?? task['price'] ?? task['budget']);
    final materials = List<Map<String, dynamic>>.from((task['materials'] ?? const <Map<String, dynamic>>[]) as List);
    final matTotal = materials.fold<int>(0, (sum, it) => sum + (_toInt(it['price']) * ((it['qty'] is num) ? (it['qty'] as num).round() : 1)));
    final tip = _toInt(task['tip']);
    final gross = base + matTotal + tip;
    final commissionCoins = _toInt(task['commissionCoins']);
    final status = (task['status'] ?? '') as String;

    pw.Widget row(String a, String b) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(a), pw.Text(b)],
    );

    doc.addPage(
      pw.Page(
        build: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Servana Receipt', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Task: $title'),
              if (taskId.isNotEmpty) pw.Text('Task ID: $taskId'),
              if (helperName?.isNotEmpty == true) pw.Text('Helper: $helperName'),
              if (posterName?.isNotEmpty == true) pw.Text('Poster: $posterName'),
              if (cat.isNotEmpty) pw.Text('Category: $cat'),
              if (type.isNotEmpty) pw.Text('Type: $type'),
              if (address.isNotEmpty) pw.Text('Address: $address'),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              row('Base price (LKR)', nf.format(base)),
              row('Materials (LKR)', nf.format(matTotal)),
              row('Tip (LKR)', nf.format(tip)),
              pw.Divider(),
              row('Gross total (LKR)', nf.format(gross)),
              pw.SizedBox(height: 12),
              pw.Text('Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: 'Commission is charged in coins (${commissionCoins > 0 ? commissionCoins : 0}) and doesn’t reduce LKR payout.'),
              pw.Bullet(text: 'Status: $status'),
              pw.SizedBox(height: 12),
              pw.Text('Thank you for using Servana.'),
            ],
          ),
        ),
      ),
    );
    return await doc.save();
  }
}
