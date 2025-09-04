import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:servana/models/user_model.dart';
import 'package:servana/widgets/recommended_helper_card.dart';

class AiRecommendationSection extends StatefulWidget {
  final HelpifyUser user;
  final String? preferredCategoryId;

  const AiRecommendationSection({
    super.key,
    required this.user,
    this.preferredCategoryId,
  });

  @override
  State<AiRecommendationSection> createState() => _AiRecommendationSectionState();
}

class _AiRecommendationSectionState extends State<AiRecommendationSection> {
  late Future<List<HelpifyUser>> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  void _loadRecommendations() {
    setState(() {
      _recommendationsFuture = _fetchAIHelperRecommendations(widget.user);
    });
  }

  /// Fetches a list of verified helpers to recommend to the user.
  
  Future<List<HelpifyUser>> _fetchAIHelperRecommendations(HelpifyUser user) async {
    final db = FirebaseFirestore.instance;
    final pref = widget.preferredCategoryId ?? (user.registeredCategories.isNotEmpty ? user.registeredCategories.first : null);

    List<HelpifyUser> list = [];
    try {
      if (pref != null && pref.isNotEmpty) {
        // Prefer helpers verified for the preferred category
        final qs = await db.collection('users')
            .where('isHelper', isEqualTo: true)
            .where('allowedCategoryIds', arrayContains: pref)
            .limit(12)
            .get();
        list = qs.docs.map((d) => HelpifyUser.fromFirestore(d)).toList();
      }
      if (list.isEmpty) {
        // Fallback: recent verified helpers
        final qs2 = await db.collection('users')
            .where('isHelper', isEqualTo: true)
            .where('verificationStatus', isEqualTo: 'verified')
            .limit(12)
            .get();
        list = qs2.docs.map((d) => HelpifyUser.fromFirestore(d)).toList();
      }

      // Soft-rank: if preferred category exists, helpers verified for it float to top
      if (pref != null && pref.isNotEmpty) {
        list.sort((a, b) {
          bool aHit = (a.badges.contains('verified') || a.isHelperVerified); // basic proxy
          bool bHit = (b.badges.contains('verified') || b.isHelperVerified);
          if (aHit != bHit) return aHit ? -1 : 1;
          return 0;
        });
      }
    } catch (_) {}

    return list;
  }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HelpifyUser>>(
      future: _recommendationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Card(child: Padding(padding: EdgeInsets.all(20.0), child: Center(child: Text("Could not load recommendations."))));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(child: Padding(padding: EdgeInsets.all(20.0), child: Center(child: Text("No recommendations available right now."))));
        }

        final items = snapshot.data!;

        return SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return RecommendedHelperCard(helper: item);
            },
          ),
        );
      },
    );
  }
}
