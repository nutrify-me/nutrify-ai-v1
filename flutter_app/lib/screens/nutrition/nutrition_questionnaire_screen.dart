import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/generation_provider.dart';

/// Region-aware food preference assessment shown before generating AI meal plans.
/// Collects food region, cooking skill, dietary restrictions, staple foods, etc.
class NutritionQuestionnaireScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const NutritionQuestionnaireScreen({super.key, this.onComplete});

  @override
  ConsumerState<NutritionQuestionnaireScreen> createState() =>
      _NutritionQuestionnaireScreenState();
}

class _NutritionQuestionnaireScreenState
    extends ConsumerState<NutritionQuestionnaireScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSubmitting = false;

  // ─── Form Data ─────────────────────────────────────
  String? _foodRegion;
  String? _cookingSkill;
  String? _cookingTime;
  String? _mealsPerDay;
  String? _dietType;
  List<String> _allergies = [];
  List<String> _stapleFoods = [];
  String _foodsToAvoid = '';
  String? _spiceTolerance;

  // ─── Region Definitions ────────────────────────────
  static const Map<String, _FoodRegionDef> _regions = {
    'indian_north': _FoodRegionDef(
      label: 'Indian (North)',
      emoji: '🇮🇳',
      desc: 'Dal, Roti, Rice, Sabzi, Paneer, Curd',
      staples: ['Dal', 'Roti/Chapati', 'Rice', 'Paneer', 'Curd/Raita', 'Paratha', 'Aloo', 'Chole', 'Rajma', 'Khichdi', 'Poha', 'Upma', 'Dahi', 'Sabzi'],
    ),
    'indian_south': _FoodRegionDef(
      label: 'Indian (South)',
      emoji: '🇮🇳',
      desc: 'Idli, Dosa, Sambar, Rice, Rasam',
      staples: ['Idli', 'Dosa', 'Sambar', 'Rice', 'Rasam', 'Upma', 'Pongal', 'Coconut Chutney', 'Curd Rice', 'Uttapam', 'Vada', 'Appam', 'Kootu'],
    ),
    'american': _FoodRegionDef(
      label: 'American',
      emoji: '🇺🇸',
      desc: 'Oatmeal, Sandwiches, Grilled Chicken, Salads',
      staples: ['Oatmeal', 'Eggs', 'Toast', 'Chicken Breast', 'Ground Turkey', 'Salad', 'Pasta', 'Sandwich', 'Burrito Bowl', 'Rice Bowl', 'Steak', 'Smoothie'],
    ),
    'mediterranean': _FoodRegionDef(
      label: 'Mediterranean',
      emoji: '🫒',
      desc: 'Hummus, Grilled Fish, Olive Oil, Feta',
      staples: ['Hummus', 'Pita', 'Grilled Fish', 'Olive Oil', 'Feta', 'Greek Yogurt', 'Tabbouleh', 'Lentil Soup', 'Falafel', 'Grilled Chicken', 'Couscous'],
    ),
    'east_asian': _FoodRegionDef(
      label: 'East Asian',
      emoji: '🥢',
      desc: 'Rice, Stir-fry, Tofu, Noodles, Miso',
      staples: ['Rice', 'Stir-fry', 'Tofu', 'Miso Soup', 'Noodles', 'Edamame', 'Steamed Fish', 'Dumplings', 'Fried Rice', 'Kimchi', 'Sushi Bowl'],
    ),
    'southeast_asian': _FoodRegionDef(
      label: 'Southeast Asian',
      emoji: '🍜',
      desc: 'Rice, Curry, Noodle Soups, Satay',
      staples: ['Rice', 'Curry', 'Noodle Soup', 'Satay', 'Spring Rolls', 'Stir-fried Vegetables', 'Coconut Curry', 'Pad Thai', 'Fried Rice', 'Banh Mi'],
    ),
    'latin_american': _FoodRegionDef(
      label: 'Latin American',
      emoji: '🌮',
      desc: 'Beans, Rice, Tortillas, Grilled Meats',
      staples: ['Rice & Beans', 'Tortillas', 'Grilled Chicken', 'Tacos', 'Burrito Bowl', 'Plantain', 'Quesadilla', 'Guacamole', 'Enchiladas', 'Ceviche'],
    ),
    'middle_eastern': _FoodRegionDef(
      label: 'Middle Eastern',
      emoji: '🧆',
      desc: 'Flatbread, Kebabs, Lentils, Yogurt',
      staples: ['Flatbread', 'Kebabs', 'Lentils', 'Yogurt', 'Hummus', 'Falafel', 'Shawarma', 'Tabbouleh', 'Rice Pilaf', 'Stuffed Grape Leaves'],
    ),
    'european': _FoodRegionDef(
      label: 'European',
      emoji: '🇪🇺',
      desc: 'Bread, Cheese, Soups, Pasta, Roasts',
      staples: ['Bread', 'Cheese', 'Soup', 'Pasta', 'Roast Chicken', 'Potatoes', 'Salad', 'Quiche', 'Risotto', 'Omelette', 'Stew'],
    ),
    'african': _FoodRegionDef(
      label: 'African',
      emoji: '🍲',
      desc: 'Injera, Stews, Rice, Plantain',
      staples: ['Injera', 'Stew', 'Rice', 'Plantain', 'Jollof Rice', 'Fufu', 'Grilled Fish', 'Lentils', 'Couscous', 'Beans'],
    ),
    'mixed': _FoodRegionDef(
      label: 'Mixed / International',
      emoji: '🌍',
      desc: 'A bit of everything from around the world',
      staples: ['Rice', 'Pasta', 'Chicken', 'Fish', 'Eggs', 'Salad', 'Bread', 'Yogurt', 'Beans', 'Tofu', 'Stir-fry', 'Soup'],
    ),
  };

  static const List<String> _dietTypes = [
    'No Restriction',
    'Vegetarian',
    'Vegan',
    'Pescatarian',
    'Keto',
    'Low Carb',
    'Halal',
    'Kosher',
    'Jain',
  ];

  static const List<String> _allergyOptions = [
    'Peanuts',
    'Tree Nuts',
    'Milk/Dairy',
    'Eggs',
    'Wheat/Gluten',
    'Soy',
    'Fish',
    'Shellfish',
    'Sesame',
    'None',
  ];

  int get _totalPages => 3;

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submitQuestionnaire();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitQuestionnaire() async {
    setState(() => _isSubmitting = true);

    try {
      final nutritionPreferences = {
        'food_region': _foodRegion,
        'cooking_skill': _cookingSkill,
        'cooking_time': _cookingTime,
        'meals_per_day': _mealsPerDay,
        'diet_type': _dietType,
        'allergies': _allergies.contains('None') ? <String>[] : _allergies,
        'staple_foods': _stapleFoods,
        'foods_to_avoid': _foodsToAvoid.trim(),
        'spice_tolerance': _spiceTolerance,
        'questionnaire_completed': true,
      };

      // Also map flat fields for the profile model
      final profileUpdate = <String, dynamic>{
        'nutrition_preferences': nutritionPreferences,
        'dietary_restrictions': _dietType != null && _dietType != 'No Restriction'
            ? [_dietType]
            : <String>[],
        'allergies': _allergies.contains('None')
            ? ''
            : _allergies.join(', '),
        'meals_per_day': _mealsPerDay != null
            ? int.tryParse(_mealsPerDay!.replaceAll(RegExp(r'[^0-9]'), ''))
            : null,
        'cooking_time': _cookingTime,
      };

      final success =
          await ref.read(authNotifierProvider.notifier).updateProfile(profileUpdate);

      if (success && mounted) {
        // Auto-trigger generation
        ref.read(generationNotifierProvider.notifier).startNutritionGeneration();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved! Generating your meal plan...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onComplete?.call();
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Failed to save preferences');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Preferences'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: (_currentPage + 1) / _totalPages,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),

          // Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _currentPage = i),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildRegionPage(theme),
                _buildDietAndRestrictionsPage(theme),
                _buildCookingAndStaplesPage(theme),
              ],
            ),
          ),

          // Nav buttons
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousPage,
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentPage > 0) const SizedBox(width: 16),
                Expanded(
                  flex: _currentPage > 0 ? 2 : 1,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _nextPage,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_currentPage == _totalPages - 1
                            ? 'Generate My Plan'
                            : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Page 1: Food Region ───────────────────────────
  Widget _buildRegionPage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you eat at home?',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Pick the cuisine closest to your daily meals. This tells the AI what kind of food to suggest.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          ..._regions.entries.map((e) {
            final key = e.key;
            final r = e.value;
            final isSelected = _foodRegion == key;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() {
                  _foodRegion = key;
                  // Reset staples when region changes
                  _stapleFoods = [];
                }),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(r.emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isSelected
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.desc,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? theme.colorScheme.onPrimaryContainer.withOpacity(0.7)
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Page 2: Diet Type & Restrictions ──────────────
  Widget _buildDietAndRestrictionsPage(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diet & Restrictions',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Any dietary rules the AI must follow?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Diet type
          Text('Diet Type', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dietTypes.map((diet) {
              final isSelected = _dietType == diet;
              return ChoiceChip(
                label: Text(diet),
                selected: isSelected,
                onSelected: (_) => setState(() => _dietType = diet),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Allergies
          Text(
            'Allergies',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'These ingredients will be completely avoided',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allergyOptions.map((allergy) {
              final isSelected = _allergies.contains(allergy);
              return FilterChip(
                label: Text(allergy),
                selected: isSelected,
                selectedColor: theme.colorScheme.errorContainer,
                onSelected: (selected) {
                  setState(() {
                    if (allergy == 'None') {
                      _allergies = selected ? ['None'] : [];
                    } else {
                      _allergies.remove('None');
                      if (selected) {
                        _allergies.add(allergy);
                      } else {
                        _allergies.remove(allergy);
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Spice tolerance
          Text('Spice Level', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Mild', 'Medium', 'Spicy'].map((level) {
              final isSelected = _spiceTolerance == level.toLowerCase();
              return ChoiceChip(
                label: Text(level),
                selected: isSelected,
                onSelected: (_) => setState(() => _spiceTolerance = level.toLowerCase()),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Foods to avoid (free text)
          Text('Foods You Dislike (optional)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => _foodsToAvoid = v,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. mushrooms, olives, bitter gourd...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Page 3: Cooking & Staple Foods ────────────────
  Widget _buildCookingAndStaplesPage(ThemeData theme) {
    final regionDef = _foodRegion != null ? _regions[_foodRegion] : null;
    final availableStaples = regionDef?.staples ?? _regions['mixed']!.staples;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cooking & Staples',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Helps the AI suggest meals you can actually make.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Cooking skill
          Text('Cooking Skill', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...['beginner', 'intermediate', 'advanced'].map((skill) {
            final labels = {
              'beginner': 'Beginner',
              'intermediate': 'Intermediate',
              'advanced': 'Advanced',
            };
            final descs = {
              'beginner': 'Simple recipes, fewer ingredients, quick prep',
              'intermediate': 'Comfortable cooking most things',
              'advanced': 'Enjoy complex recipes and techniques',
            };
            final isSelected = _cookingSkill == skill;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _cookingSkill = skill),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(labels[skill]!, style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface)),
                            Text(descs[skill]!, style: TextStyle(fontSize: 12, color: isSelected ? theme.colorScheme.onPrimaryContainer.withOpacity(0.7) : theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (isSelected) Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 24),

          // Cooking time
          Text('Cooking Time Per Meal', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['15 min', '30 min', '45 min', '60+ min'].map((time) {
              final isSelected = _cookingTime == time;
              return ChoiceChip(
                label: Text(time),
                selected: isSelected,
                onSelected: (_) => setState(() => _cookingTime = time),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Meals per day
          Text('Meals Per Day', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['2 meals', '3 meals', '4 meals'].map((m) {
              final isSelected = _mealsPerDay == m;
              return ChoiceChip(
                label: Text(m),
                selected: isSelected,
                onSelected: (_) => setState(() => _mealsPerDay = m),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Staple foods (dynamic based on region)
          Text('Your Staple Foods', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Tap the foods you eat regularly. The AI will build meals around these.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableStaples.map((food) {
              final isSelected = _stapleFoods.contains(food);
              return FilterChip(
                label: Text(food),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _stapleFoods.add(food);
                    } else {
                      _stapleFoods.remove(food);
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Tip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your AI meal plan will use simple, everyday recipes from your region with step-by-step cooking instructions.',
                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper class ──────────────────────────────────
class _FoodRegionDef {
  final String label;
  final String emoji;
  final String desc;
  final List<String> staples;

  const _FoodRegionDef({
    required this.label,
    required this.emoji,
    required this.desc,
    required this.staples,
  });
}
