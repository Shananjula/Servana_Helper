import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:servana/providers/user_provider.dart';
import 'package:servana/utils/verification_nav.dart';

// --- FIX: The TaskMode enum is now defined here, making this widget self-contained ---
enum TaskMode { physical, online }

class Category {
  final String name;
  final IconData icon;
  final Color color;

  Category({required this.name, required this.icon, required this.color});
}

class CategoryGridView extends StatelessWidget {
  final Function(String) onCategoryTap;
  final TaskMode taskMode;
  final bool guardForHelper;

  const CategoryGridView({
    super.key,
    required this.onCategoryTap,
    required this.taskMode,
  });

  @override
  Widget build(BuildContext context) {
    final List<Category> physicalCategories = [
      Category(name: 'Home Tutoring', icon: Icons.school_rounded, color: const Color(0xFF8E44AD)),
      Category(name: 'Rider', icon: Icons.motorcycle_rounded, color: const Color(0xFF27AE60)),
      Category(name: 'Cleaning', icon: Icons.cleaning_services_rounded, color: const Color(0xFF2980B9)),
      Category(name: 'Handyman', icon: Icons.handyman_rounded, color: const Color(0xFFD35400)),
      Category(name: 'Moving', icon: Icons.local_shipping_rounded, color: const Color(0xFFC0392B)),
      Category(name: 'Gardening', icon: Icons.grass_rounded, color: const Color(0xFF16A085)),
      Category(name: 'Appliance', icon: Icons.kitchen_rounded, color: const Color(0xFFF39C12)),
      Category(name: 'Assembly', icon: Icons.build_circle_rounded, color: const Color(0xFF7F8C8D)),
    ];

    final List<Category> onlineCategories = [
      Category(name: 'Home Tutoring', icon: Icons.school_rounded, color: const Color(0xFF8E44AD)),
      Category(name: 'Design', icon: Icons.palette_rounded, color: const Color(0xFFC0392B)),
      Category(name: 'Writing', icon: Icons.edit_note_rounded, color: const Color(0xFF2980B9)),
      Category(name: 'Marketing', icon: Icons.campaign_rounded, color: const Color(0xFF27AE60)),
      Category(name: 'Tech', icon: Icons.code_rounded, color: const Color(0xFF16A085)),
      Category(name: 'Video', icon: Icons.videocam_rounded, color: const Color(0xFFD35400)),
      Category(name: 'Business', icon: Icons.business_center_rounded, color: const Color(0xFF7F8C8D)),
      Category(name: 'Lifestyle', icon: Icons.self_improvement_rounded, color: const Color(0xFFF39C12)),
    ];

    final categories = taskMode == TaskMode.physical ? physicalCategories : onlineCategories;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return GestureDetector(
          onTap: () => onCategoryTap(category.name),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: category.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(category.icon, size: 30, color: category.color),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
