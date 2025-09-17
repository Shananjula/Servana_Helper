import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BackfillToolsScreen extends StatefulWidget {
  const BackfillToolsScreen({super.key});

  @override
  State<BackfillToolsScreen> createState() => _BackfillToolsScreenState();
}

class _BackfillToolsScreenState extends State<BackfillToolsScreen> {
  final _taskIdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _running = false;
  String _log = '';

  void _appendLog(Object msg) {
    setState(() {
      final line = (msg is Map || msg is List)
          ? const JsonEncoder.withIndent('  ').convert(msg)
          : msg.toString();
      _log += '${DateTime.now().toIso8601String()}  $line\n';
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _ensureSignedIn() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in. Please sign in first.');
    }
  }

  Future<void> _enableDebugMode() async {
    await _ensureSignedIn();
    await FirebaseFirestore.instance
        .doc('settings/platform')
        .set({'debugMode': true}, SetOptions(merge: true));
    _appendLog('✅ settings/platform.debugMode set to true');
  }

  Future<Map<String, dynamic>> _callAll({
    required bool dryRun,
    int limitTasks = 200,
    int limitOffersPerTask = 1000,
    String? startAfterTaskId,
    bool onlyMissing = true,
  }) async {
    final fn = FirebaseFunctions.instance.httpsCallable('backfillAllOffersPosterId');
    final res = await fn.call({
      'dryRun': dryRun,
      'limitTasks': limitTasks,
      'limitOffersPerTask': limitOffersPerTask,
      'onlyMissing': onlyMissing,
      if (startAfterTaskId != null) 'startAfterTaskId': startAfterTaskId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> _callSingle(String taskId) async {
    final fn = FirebaseFunctions.instance.httpsCallable('backfillOffersPosterId');
    final res = await fn.call({'taskId': taskId});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> _runDry() async {
    if (_running) return;
    setState(() => _running = true);
    _appendLog('▶️ DRY RUN: scanning ~200 tasks (no writes)…');
    try {
      await _ensureSignedIn();
      final out = await _callAll(dryRun: true, limitTasks: 200, limitOffersPerTask: 1000);
      _appendLog(out);
      _appendLog('✅ Dry run complete.');
    } on FirebaseFunctionsException catch (e) {
      _appendLog('❌ Functions error: ${e.code} ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _runGlobal() async {
    if (_running) return;
    setState(() => _running = true);
    _appendLog('▶️ LIVE BACKFILL: patching all missing posterId in offers…');
    try {
      await _ensureSignedIn();
      String? cursor;
      int pages = 0;
      int totalPatched = 0;
      while (true) {
        final out = await _callAll(
          dryRun: false,
          limitTasks: 200,
          limitOffersPerTask: 1000,
          startAfterTaskId: cursor,
          onlyMissing: true,
        );
        pages++;
        totalPatched += (out['patched'] as int? ?? 0);
        _appendLog({'page': pages, ...out});
        cursor = out['nextStartAfterTaskId'] as String?;
        if (cursor == null) break;
      }
      _appendLog('✅ LIVE BACKFILL DONE. pages=$pages, totalPatched=$totalPatched');
    } on FirebaseFunctionsException catch (e) {
      _appendLog('❌ Functions error: ${e.code} ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _runSingle() async {
    if (_running) return;
    final tid = _taskIdCtrl.text.trim();
    if (tid.isEmpty) {
      _appendLog('⚠️ Enter a taskId first.');
      return;
    }
    setState(() => _running = true);
    _appendLog('▶️ Single-task backfill: $tid');
    try {
      await _ensureSignedIn();
      final out = await _callSingle(tid);
      _appendLog(out);
      _appendLog('✅ Single-task backfill complete.');
    } on FirebaseFunctionsException catch (e) {
      _appendLog('❌ Functions error: ${e.code} ${e.message}');
    } catch (e) {
      _appendLog('❌ Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _taskIdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Backfill Tools — offers.posterId')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('UID: $uid', maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _running ? null : _enableDebugMode,
                  child: const Text('Enable debugMode'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _running ? null : _runDry,
                  child: const Text('Dry run (no writes)'),
                ),
                FilledButton(
                  onPressed: _running ? null : _runGlobal,
                  child: const Text('Run global backfill'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'taskId for single-task backfill',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _running ? null : _runSingle,
                  child: const Text('Run'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _scrollCtrl,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _log.isEmpty ? 'Logs will appear here…' : _log,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
