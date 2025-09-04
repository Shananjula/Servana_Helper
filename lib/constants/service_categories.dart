// lib/constants/service_categories.dart
//
// Canonical service categories + swappable "icon packs"
// AND legacy compatibility: AppServices.categories (Map<label, List<subcats>>)

import 'package:flutter/material.dart';

enum CategoryIconPack { material, emoji, threed }

class AppServices {
  // ---------------- Master list ----------------
  static const Map<String, String> idToLabel = {
    'cleaning': 'Cleaning',
    'delivery': 'Delivery',
    'repairs': 'Repairs',
    'tutoring': 'Tutoring',
    'design': 'Design',
    'writing': 'Writing',
    'moving': 'Moving',
    'gardening': 'Gardening',
    'tech_support': 'Tech support',
    'beauty': 'Beauty',
  };

  static const Map<String, String> labelToId = {
    'Cleaning': 'cleaning',
    'Delivery': 'delivery',
    'Repairs': 'repairs',
    'Tutoring': 'tutoring',
    'Design': 'design',
    'Writing': 'writing',
    'Moving': 'moving',
    'Gardening': 'gardening',
    'Tech support': 'tech_support',
    'Beauty': 'beauty',
  };

  static const List<String> allIds = [
    'cleaning',
    'delivery',
    'repairs',
    'tutoring',
    'design',
    'writing',
    'moving',
    'gardening',
    'tech_support',
    'beauty',
  ];

  // ---------------- LEGACY COMPAT: group → subcategories ----------------
  // post_task_screen.dart iterates AppServices.categories.entries/keys
  static const Map<String, List<String>> categories = {
    'Cleaning': [
      'House cleaning',
      'Deep cleaning',
      'Laundry',
      'Window cleaning',
      'Post-renovation',
    ],
    'Delivery': [
      'Parcel delivery',
      'Food pickup',
      'Grocery run',
      'Documents',
    ],
    'Repairs': [
      'Electrical',
      'Plumbing',
      'Carpentry',
      'AC/Appliance',
      'Auto repair',
    ],
    'Tutoring': [
      'Math',
      'Science',
      'Languages',
      'ICT',
      'Exam prep',
    ],
    'Design': [
      'Graphic design',
      'Logo/Branding',
      'UI/UX',
      'Illustration',
    ],
    'Writing': [
      'Copywriting',
      'Blog/article',
      'Editing/Proofread',
      'Translation',
    ],
    'Moving': [
      'Local move',
      'Packing',
      'Furniture moving',
      'Pickup with driver',
    ],
    'Gardening': [
      'Lawn mowing',
      'Hedge/Tree trim',
      'Landscaping',
      'Plant care',
    ],
    'Tech support': [
      'Phone setup',
      'PC troubleshooting',
      'Network/Wi-Fi',
      'Data backup',
    ],
    'Beauty': [
      'Haircut',
      'Makeup',
      'Manicure/Pedicure',
      'Spa/Massage',
    ],
  };

  // ---------------- Swappable icon packs ----------------
  static CategoryIconPack iconPack = CategoryIconPack.threed; // swap style here

  static const Map<String, IconData> _material = {
    'cleaning': Icons.cleaning_services,
    'delivery': Icons.delivery_dining,
    'repairs': Icons.build,
    'tutoring': Icons.menu_book,
    'design': Icons.brush,
    'writing': Icons.edit,
    'moving': Icons.local_shipping_outlined,
    'gardening': Icons.grass_outlined,
    'tech_support': Icons.support_agent_outlined,
    'beauty': Icons.spa_outlined,
  };

  static const Map<String, String> _emoji = {
    'cleaning': '🧹',
    'delivery': '📦',
    'repairs': '🔧',
    'tutoring': '📚',
    'design': '🎨',
    'writing': '✍️',
    'moving': '🚚',
    'gardening': '🌿',
    'tech_support': '🛠️',
    'beauty': '💆‍♀️',
  };

  static const Map<String, String> _threedAsset = {
    'cleaning': 'assets/categories/3d/cleaning.png',
    'delivery': 'assets/categories/3d/delivery.png',
    'repairs': 'assets/categories/3d/repairs.png',
    'tutoring': 'assets/categories/3d/tutoring.png',
    'design': 'assets/categories/3d/design.png',
    'writing': 'assets/categories/3d/writing.png',
    'moving': 'assets/categories/3d/moving.png',
    'gardening': 'assets/categories/3d/gardening.png',
    'tech_support': 'assets/categories/3d/tech_support.png',
    'beauty': 'assets/categories/3d/beauty.png',
  };

  // ---------------- Tile gradients ----------------
  static List<Color> categoryGradient(String id, {Brightness? brightness}) {
    final b = brightness ?? Brightness.light;
    switch (id) {
      case 'cleaning':
        return b == Brightness.dark
            ? [const Color(0xFF2A6CF7), const Color(0xFF3BC6FF)]
            : [const Color(0xFF4F8BFF), const Color(0xFF7ED3FF)];
      case 'delivery':
        return b == Brightness.dark
            ? [const Color(0xFF09B27A), const Color(0xFF45E1A7)]
            : [const Color(0xFF34C38F), const Color(0xFF8FE3C7)];
      case 'repairs':
        return b == Brightness.dark
            ? [const Color(0xFFED6A00), const Color(0xFFFFB36B)]
            : [const Color(0xFFFF8A3D), const Color(0xFFFFC996)];
      case 'tutoring':
        return b == Brightness.dark
            ? [const Color(0xFF6741FF), const Color(0xFFA18CFF)]
            : [const Color(0xFF7C5CFF), const Color(0xFFC3B8FF)];
      case 'design':
        return b == Brightness.dark
            ? [const Color(0xFFEE3B88), const Color(0xFFFF86B9)]
            : [const Color(0xFFFF5CA8), const Color(0xFFFFA9D0)];
      case 'writing':
        return b == Brightness.dark
            ? [const Color(0xFF15AABF), const Color(0xFF69DCEB)]
            : [const Color(0xFF33C9DF), const Color(0xFF90E7F3)];
      case 'moving':
        return b == Brightness.dark
            ? [const Color(0xFF0EA5E9), const Color(0xFF67C3FF)]
            : [const Color(0xFF42B4F5), const Color(0xFF9ADAFF)];
      case 'gardening':
        return b == Brightness.dark
            ? [const Color(0xFF00B25C), const Color(0xFF63E59B)]
            : [const Color(0xFF25C06F), const Color(0xFF9BF0C3)];
      case 'tech_support':
        return b == Brightness.dark
            ? [const Color(0xFF5E5DF0), const Color(0xFF93A4FF)]
            : [const Color(0xFF7C7BF9), const Color(0xFFB7C2FF)];
      case 'beauty':
        return b == Brightness.dark
            ? [const Color(0xFFFF5B7F), const Color(0xFFFF95B0)]
            : [const Color(0xFFFF7097), const Color(0xFFFFB3CB)];
      default:
        return b == Brightness.dark
            ? [const Color(0xFF5B8CFF), const Color(0xFF9CC4FF)]
            : [const Color(0xFF5B8CFF), const Color(0xFF9CC4FF)];
    }
  }

  // ---------------- Icon renderer ----------------
  static Widget categoryIconWidget(String id, {double size = 28, Color? color}) {
    switch (iconPack) {
      case CategoryIconPack.emoji:
        final emoji = _emoji[id] ?? '🔹';
        return Text(emoji, style: TextStyle(fontSize: size * 0.9));
      case CategoryIconPack.threed:
        final asset = _threedAsset[id];
        if (asset != null) {
          return Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(_material[id] ?? Icons.work_outline, size: size, color: color),
          );
        }
        return Icon(_material[id] ?? Icons.work_outline, size: size, color: color);
      case CategoryIconPack.material:
      default:
        return Icon(_material[id] ?? Icons.work_outline, size: size, color: color);
    }
  }

  // ---------------- Utils ----------------
  static String idForLabel(String label) =>
      labelToId[label] ?? label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  static String labelForId(String id) =>
      idToLabel[id] ?? (id.isEmpty ? id : id[0].toUpperCase() + id.substring(1).replaceAll('_', ' '));
}
