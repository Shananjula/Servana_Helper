// lib/widgets/make_offer_sheet.dart
import 'package:flutter/material.dart';
import 'package:servana/services/offer_service.dart';

class MakeOfferSheet extends StatefulWidget {
  final String taskId;
  const MakeOfferSheet({super.key, required this.taskId});

  @override
  State<MakeOfferSheet> createState() => _MakeOfferSheetState();
}

class _MakeOfferSheetState extends State<MakeOfferSheet> {
  final _form = GlobalKey<FormState>();
  final _price = TextEditingController();
  final _msg = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _price.dispose();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _posting = true);
    try {
      await OfferService().createOffer(
        taskId: widget.taskId,
        price: num.parse(_price.text.trim()),
        message: _msg.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          top: 16,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Make an Offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _msg,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Message (optional)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _posting ? null : _submit,
                icon: const Icon(Icons.send),
                label: Text(_posting ? 'Sending...' : 'Send Offer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
