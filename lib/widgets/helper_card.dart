import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:servana/providers/user_provider.dart';
import 'package:servana/services/firestore_service.dart';
import 'package:servana/screens/helper_public_profile_screen.dart';

/// HelperCard – tolerant to missing fields on the model passed in.
/// It tries to access common properties via `dynamic` and falls back safely.
class HelperCard extends StatelessWidget {
  const HelperCard({
    super.key,
    required this.data,
    this.onViewProfile,
    this.contextCategoryId, // 👈 normalized id, e.g. 'plumbing'
    this.contextCategoryLabel, // 👈 pretty label, e.g. 'Plumbing'
  });

  final Map<String, dynamic> data;
  final VoidCallback? onViewProfile;
  final String? contextCategoryId;
  final String? contextCategoryLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = FirestoreService.instance;

    // --- Compute derived properties from `data` ---
    final String name = _str(() => data['displayName']) ?? _str(() => data['name']) ?? 'Helper';
    final bool isPro = _bool(() => data['isProMember']) ?? false;
    final List<String> skills = _list(() => data['skills']) ?? const <String>[];
    final String? helperId = _str(() => data['id']) ?? _str(() => data['uid']) ?? _str(() => data['userId']);

    // --- Compute category verification status ---
    final allowed = (data['allowedCategoryIds'] is List)
        ? List<String>.from(data['allowedCategoryIds']).map((s) => s.toLowerCase()).toSet()
        : <String>{};
    final String? catId = contextCategoryId?.toLowerCase();
    final bool isCatVerified = catId != null && catId.isNotEmpty && allowed.contains(catId);
    final String label = (contextCategoryLabel ?? contextCategoryId ?? '').toString().replaceAll('_', ' ');

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withOpacity(0.12)),
      ),
      child: ListTile(
        onTap: onViewProfile ??
            (helperId == null
                ? null
                : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: helperId)),
            )),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (isPro) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'PRO',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (skills.isNotEmpty)
              Text(
                skills.take(3).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            // --- Render the verified chip ---
            if (isCatVerified) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(label.isEmpty ? 'Verified' : 'Verified • $label'),
                  backgroundColor: Colors.green.withOpacity(0.14),
                  labelStyle: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w800),
                  side: BorderSide(color: Colors.green.withOpacity(0.25)),
                ),
              ),
            ],
            // Fallback: if no context category provided but helper has any allowed categories, show generic Verified
            else if (!isCatVerified && (allowed.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Verified'),
                  backgroundColor: Colors.green.withOpacity(0.14),
                  labelStyle: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w800),
                  side: BorderSide(color: Colors.green.withOpacity(0.25)),
                ),
              ),
            ],

          ],
        ),
        trailing: helperId == null
            ? null
            : FilledButton.tonal(
          onPressed: () async {
            final currentUid = context.read<UserProvider>().uid;
            if (currentUid == null || helperId == null || currentUid == helperId) return;

            final channelId = await fs.initiateDirectContact(currentUid, helperId);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Chat channel ready: $channelId')),
            );
          },
          child: const Text('Message'),
        ),
      ),
    );
  }
}

// ---- tolerant accessors (avoid runtime crashes if fields missing) ----
String? _str(String? Function() getter) {
  try {
    final v = getter();
    if (v == null || v.toString().trim().isEmpty) return null;
    return v.toString().trim();
  } catch (_) {
    return null;
  }
}

bool? _bool(bool? Function() getter) {
  try {
    final v = getter();
    return v == true;
  } catch (_) {
    return null;
  }
}

List<String>? _list(List? Function() getter) {
  try {
    final v = getter();
    if (v == null) return null;
    return v.whereType<String>().toList();
  } catch (_) {
    return null;
  }
}

GeoPoint? _geo(dynamic Function() getter) {
  try {
    final v = getter();
    if (v is GeoPoint) return v;
    return null;
  } catch (_) {
    return null;
  }
}
