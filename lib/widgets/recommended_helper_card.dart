import 'package:flutter/material.dart';
import 'package:servana/models/user_model.dart';
// --- FIX: Import the correct public profile screen ---
import 'package:servana/screens/helper_public_profile_screen.dart';

class RecommendedHelperCard extends StatelessWidget {
  final HelpifyUser helper;

  const RecommendedHelperCard({super.key, required this.helper});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // --- FIX: Changed ProfileScreen to HelperPublicProfileScreen ---
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HelperPublicProfileScreen(helperId: helper.id))),
        child: Container(
            width: 160,
            padding: const EdgeInsets.all(12),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(radius: 35, backgroundImage: helper.photoURL != null ? NetworkImage(helper.photoURL!
                if (helper.isHelperVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Verified'),
                      backgroundColor: Colors.green.withOpacity(0.14),
                      labelStyle: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w800),
                      side: BorderSide(color: Colors.green.withOpacity(0.25)),
                    ),
                  ),
) : null, child: helper.photoURL == null ? const Icon(Icons.person) : null),
                  const SizedBox(height: 12),
                  Text(helper.displayName ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if(helper.skills.isNotEmpty)
                    Text(helper.skills.first, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)
                ]
            )
        ),
      ),
    );
  }
}