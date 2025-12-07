import 'package:flutter/material.dart';

import '../models/news_models.dart';
import '../core/constants/app_constants.dart';

class NewsCategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const NewsCategoryFilter({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'all':
        return 'All';
      case 'local_events':
        return 'Events';
      case 'professional_dev':
        return 'Professional';
      case 'career_opportunities':
        return 'Career';
      case 'education':
        return 'Education';
      case 'technology':
        return 'Tech';
      case 'productivity':
        return 'Productivity';
      default:
        return category;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'all':
        return Icons.all_inclusive;
      case 'local_events':
        return Icons.location_on;
      case 'professional_dev':
        return Icons.trending_up;
      case 'career_opportunities':
        return Icons.work;
      case 'education':
        return Icons.school;
      case 'technology':
        return Icons.computer;
      case 'productivity':
        return Icons.speed;
      default:
        return Icons.article;
    }
  }

  Color _getCategoryColor(String category, BuildContext context) {
    switch (category) {
      case 'all':
        return Theme.of(context).colorScheme.primary;
      case 'local_events':
        return Colors.orange;
      case 'professional_dev':
        return Colors.blue;
      case 'career_opportunities':
        return Colors.indigo;
      case 'education':
        return Colors.teal;
      case 'technology':
        return Colors.cyan;
      case 'productivity':
        return Colors.green;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingS),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = selectedCategory == category;
          final categoryColor = _getCategoryColor(category, context);

          return Padding(
            padding: const EdgeInsets.only(right: AppConstants.spacingS),
            child: FilterChip(
              avatar: Icon(
                _getCategoryIcon(category),
                size: 16,
                color: isSelected
                    ? Colors.white
                    : categoryColor,
              ),
              label: Text(_getCategoryDisplayName(category)),
              selected: isSelected,
              onSelected: (selected) {
                onCategorySelected(category);
              },
              backgroundColor: Colors.transparent,
              selectedColor: categoryColor,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : categoryColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              side: BorderSide(
                color: categoryColor,
                width: isSelected ? 0 : 1,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }
}
