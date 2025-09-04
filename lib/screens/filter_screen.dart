import 'package:flutter/material.dart';
import 'package:servana/constants/service_categories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Filter bottom sheet — Helper app (no role-based search)
/// -------------------------------------------------------
/// • Removes any role/search-type toggle; shows only Helper-facing filters
/// • Keeps: category, distance, budget/rate, verified-only switch, AI text (optional)
/// • Reads/writes the following keys in the returned map:
///   - category: String? (normalized id from ServiceCategories)
///   - distance: double (km)
///   - rate_min: double
///   - rate_max: double
///   - isVerified: bool
class FilterScreen extends StatefulWidget {
  final ScrollController scrollController;
  final Map<String, dynamic> initialFilters;

  const FilterScreen({super.key, required this.scrollController, required this.initialFilters});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late Map<String, dynamic> _filters;

  // UI state
  String? _selectedCategory;
  double _distanceKm = 50.0; // 1..50 (50 = any)
  RangeValues _rateRange = const RangeValues(0, 50000);
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    _filters = Map<String, dynamic>.from(widget.initialFilters);

    _selectedCategory = _filters['category'] as String?;
    _distanceKm = (_filters['distance'] as num?)?.toDouble() ?? 50.0;
    _rateRange = RangeValues(
      ((_filters['rate_min'] as num?) ?? 0).toDouble(),
      ((_filters['rate_max'] as num?) ?? 50000).toDouble(),
    );
    _verifiedOnly = (_filters['isVerified'] as bool?) ?? false;

    // Hard-remove any legacy role/searchType keys to avoid upstream confusion
    _filters.remove('role');
    _filters.remove('searchType');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Grab handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filters', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    TextButton(onPressed: _resetAll, child: const Text('Reset All')),
                  ],
                ),
                const SizedBox(height: 20),

                // Category chips
                _buildSectionHeader('Category', theme),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceCategories.all
                      .map((c) => ChoiceChip(
                    label: Text(c.label),
                    selected: _selectedCategory == c.id,
                    onSelected: (v) => setState(() => _selectedCategory = v ? c.id : null),
                  ))
                      .toList(),
                ),

                const SizedBox(height: 24),

                // Distance
                _buildSectionHeader('Distance (km)', theme),
                Column(
                  children: [
                    Slider(
                      value: _distanceKm,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: _distanceKm < 50 ? '${_distanceKm.round()} km' : '50+ km (Any)',
                      onChanged: (v) => setState(() => _distanceKm = v),
                    ),
                    Text(
                      _distanceKm < 50 ? 'Within ${_distanceKm.round()} km' : 'Any Distance',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Budget / rate
                _buildSectionHeader('Budget / Rate (LKR)', theme),
                RangeSlider(
                  values: _rateRange,
                  min: 0,
                  max: 50000,
                  divisions: 100,
                  labels: RangeLabels('LKR ${_rateRange.start.round()}', 'LKR ${_rateRange.end.round()}'),
                  onChanged: (values) => setState(() => _rateRange = values),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('LKR ${_rateRange.start.round()}', style: theme.textTheme.bodySmall),
                    Text('LKR ${_rateRange.end.round()}', style: theme.textTheme.bodySmall),
                  ],
                ),

                const SizedBox(height: 24),

                // Trust & Safety
                _buildSectionHeader('Trust & Safety', theme),
                SwitchListTile(
                  title: const Text('Verified Helpers Only'),
                  value: _verifiedOnly,
                  onChanged: (v) => setState(() => _verifiedOnly = v),
                  secondary: Icon(Icons.verified_user_outlined, color: theme.colorScheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.grey.withOpacity(0.08),
                ),
              ],
            ),
          ),

          // Apply button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _apply,
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _filters.clear();
      _selectedCategory = null;
      _distanceKm = 50.0;
      _rateRange = const RangeValues(0, 50000);
      _verifiedOnly = false;
    });
  }

  void _apply() {
    _filters['category'] = _selectedCategory;
    _filters['distance'] = _distanceKm;
    _filters['rate_min'] = _rateRange.start;
    _filters['rate_max'] = _rateRange.end;
    _filters['isVerified'] = _verifiedOnly;

    // Make sure legacy role keys don’t leak back
    _filters.remove('role');
    _filters.remove('searchType');

    Navigator.of(context).pop(_filters);
  }

  Widget _buildSectionHeader(String title, ThemeData theme) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      );
}
