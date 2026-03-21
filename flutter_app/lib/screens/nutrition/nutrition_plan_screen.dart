import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/nutrition_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progress_provider.dart';
import '../../providers/generation_provider.dart';
import '../../models/progress.dart';
import '../../models/nutrition.dart';
import '../../widgets/common/loading_overlay.dart';
import '../../services/api_service.dart';
import '../../services/request_cache_service.dart';
import 'nutrition_questionnaire_screen.dart';

class NutritionPlanScreen extends ConsumerStatefulWidget {
  const NutritionPlanScreen({super.key});

  @override
  ConsumerState<NutritionPlanScreen> createState() => _NutritionPlanScreenState();
}

class _NutritionPlanScreenState extends ConsumerState<NutritionPlanScreen> {
  int _selectedDay = DateTime.now().weekday; // 1=Monday, 7=Sunday

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nutritionNotifierProvider.notifier).loadCurrentPlan();
      ref.read(progressNotifierProvider.notifier).loadProgressEntries();

      // Setup generation completion callbacks
      final generationNotifier = ref.read(generationNotifierProvider.notifier);
      generationNotifier.onNutritionComplete = (resultId) {
        // Invalidate API cache and force reload from server
        requestCache.invalidate('nutrition_plan_current');
        ref.read(nutritionNotifierProvider.notifier).loadCurrentPlan(forceRefresh: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Your new meal plan is ready!')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      };
      generationNotifier.onNutritionError = (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Generation failed: $error')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final nutritionState = ref.watch(nutritionNotifierProvider);
    final profile = ref.watch(authNotifierProvider).profile;
    final progressState = ref.watch(progressNotifierProvider);
    final generationState = ref.watch(generationNotifierProvider);
    final currentPlan = nutritionState.currentPlan;
    final nutritionTask = generationState.nutritionTask;
    final isGenerating = nutritionTask?.isActive ?? false;

    // Get daily targets from AI-generated nutrition plan
    final calorieTarget = currentPlan?.dailyCalories ?? _calculateCalorieTarget(profile);
    // Backend returns 'protein', 'carbs', 'fat' (not with _grams suffix)
    final proteinTarget = (currentPlan?.macros['protein'] as num?)?.toInt() ??
                         (calorieTarget * 0.3 / 4).round();
    final carbsTarget = (currentPlan?.macros['carbs'] as num?)?.toInt() ??
                       (calorieTarget * 0.4 / 4).round();
    final fatTarget = (currentPlan?.macros['fat'] as num?)?.toInt() ??
                     (calorieTarget * 0.3 / 9).round();

    // Get selected day's meals from the plan
    DailyMeal? selectedDayMeals;
    if (currentPlan?.meals != null && currentPlan!.meals.isNotEmpty) {
      try {
        selectedDayMeals = currentPlan.meals.firstWhere(
          (meal) => _getDayNumber(meal.day) == _selectedDay,
        );
      } catch (e) {
        selectedDayMeals = currentPlan.meals.first;
      }
    }

    // Get today's progress for consumed values
    final todayDate = DateTime.now().toIso8601String().split('T')[0];
    ProgressEntry? todayProgress;

    try {
      todayProgress = progressState.entries.firstWhere(
        (entry) => entry.entryDate.startsWith(todayDate),
      );
    } catch (e) {
      // No entry for today
      todayProgress = null;
    }

    // Calculate consumed values from today's meals in the AI-generated plan
    // These represent the planned intake for today
    final consumedCalories = selectedDayMeals != null ? (
      selectedDayMeals.breakfast.fold<int>(0, (sum, meal) => sum + meal.calories) +
      selectedDayMeals.lunch.fold<int>(0, (sum, meal) => sum + meal.calories) +
      selectedDayMeals.dinner.fold<int>(0, (sum, meal) => sum + meal.calories) +
      selectedDayMeals.snacks.fold<int>(0, (sum, meal) => sum + meal.calories)
    ) : 0;

    final consumedProtein = selectedDayMeals != null ? (
      selectedDayMeals.breakfast.fold<double>(0, (sum, meal) => sum + meal.proteinGrams) +
      selectedDayMeals.lunch.fold<double>(0, (sum, meal) => sum + meal.proteinGrams) +
      selectedDayMeals.dinner.fold<double>(0, (sum, meal) => sum + meal.proteinGrams) +
      selectedDayMeals.snacks.fold<double>(0, (sum, meal) => sum + meal.proteinGrams)
    ).toInt() : 0;

    final consumedCarbs = selectedDayMeals != null ? (
      selectedDayMeals.breakfast.fold<double>(0, (sum, meal) => sum + meal.carbsGrams) +
      selectedDayMeals.lunch.fold<double>(0, (sum, meal) => sum + meal.carbsGrams) +
      selectedDayMeals.dinner.fold<double>(0, (sum, meal) => sum + meal.carbsGrams) +
      selectedDayMeals.snacks.fold<double>(0, (sum, meal) => sum + meal.carbsGrams)
    ).toInt() : 0;

    final consumedFat = selectedDayMeals != null ? (
      selectedDayMeals.breakfast.fold<double>(0, (sum, meal) => sum + meal.fatGrams) +
      selectedDayMeals.lunch.fold<double>(0, (sum, meal) => sum + meal.fatGrams) +
      selectedDayMeals.dinner.fold<double>(0, (sum, meal) => sum + meal.fatGrams) +
      selectedDayMeals.snacks.fold<double>(0, (sum, meal) => sum + meal.fatGrams)
    ).toInt() : 0;

    final authState = ref.watch(authNotifierProvider);
    final hasAssessment = authState.profile?.nutritionPreferences != null &&
        (authState.profile!.nutritionPreferences!['questionnaire_completed'] == true) &&
        (authState.profile!.nutritionPreferences!['food_region'] != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () {
              context.push('/food-scanner');
            },
            tooltip: 'Scan Food',
          ),
          // Regenerate button - always visible so users can redo plan
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: nutritionState.isLoading ? null : () => _showRegenerateDialog(context, ref),
            tooltip: 'Regenerate Plan',
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: nutritionState.isLoading && !isGenerating,
        child: Column(
          children: [
            // Background Generation Progress Banner
            if (isGenerating)
              _buildGenerationBanner(context, nutritionTask!),

            // Day Selector
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final dayNumber = index + 1; // 1=Monday, 7=Sunday
                  final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                  final isSelected = dayNumber == _selectedDay;
                  final isToday = dayNumber == DateTime.now().weekday;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(dayNames[index]),
                      selected: isSelected,
                      showCheckmark: false,
                      avatar: isToday && !isSelected
                          ? const Icon(Icons.circle, size: 8)
                          : null,
                      onSelected: (selected) {
                        setState(() {
                          _selectedDay = dayNumber;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Daily Summary Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today\'s Summary',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMacroColumn(context, 'Calories', consumedCalories.toString(), calorieTarget.toString(), Colors.orange),
                          _buildMacroColumn(context, 'Protein', '${consumedProtein}g', '${proteinTarget}g', Colors.red),
                          _buildMacroColumn(context, 'Carbs', '${consumedCarbs}g', '${carbsTarget}g', Colors.blue),
                          _buildMacroColumn(context, 'Fat', '${consumedFat}g', '${fatTarget}g', Colors.green),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Meal Plan
              Text(
                'Today\'s Meal Plan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              if (currentPlan == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasAssessment ? Icons.restaurant_menu : Icons.assignment_late,
                          size: 80,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          hasAssessment ? 'No Nutrition Plan Yet' : 'Complete Assessment',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasAssessment
                              ? 'Generate a personalized meal plan based on your goals and preferences.'
                              : 'To generate a personalized plan, we first need to understand your preferences.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: hasAssessment
                              ? () => _startGeneration(context, ref)
                              : () => _showNutritionQuestionnaire(context),
                          icon: Icon(hasAssessment ? Icons.auto_awesome : Icons.assignment),
                          label: Text(hasAssessment ? 'Generate Plan with AI' : 'Start Assessment'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (currentPlan != null && selectedDayMeals?.breakfast.isNotEmpty == true)
                ...selectedDayMeals!.breakfast.map((meal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildMealCard(
                    context,
                    meal,
                    'Breakfast',
                    meal.name,
                    '${meal.calories} kcal',
                    Icons.wb_sunny,
                    Colors.orange,
                  ),
                )),

              if (currentPlan != null && selectedDayMeals?.lunch.isNotEmpty == true)
                ...selectedDayMeals!.lunch.map((meal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildMealCard(
                    context,
                    meal,
                    'Lunch',
                    meal.name,
                    '${meal.calories} kcal',
                    Icons.wb_cloudy,
                    Colors.blue,
                  ),
                )),

              if (currentPlan != null && selectedDayMeals?.snacks.isNotEmpty == true)
                ...selectedDayMeals!.snacks.map((meal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildMealCard(
                    context,
                    meal,
                    'Snack',
                    meal.name,
                    '${meal.calories} kcal',
                    Icons.coffee,
                    Colors.brown,
                  ),
                )),

              if (currentPlan != null && selectedDayMeals?.dinner.isNotEmpty == true)
                ...selectedDayMeals!.dinner.map((meal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildMealCard(
                    context,
                    meal,
                    'Dinner',
                    meal.name,
                    '${meal.calories} kcal',
                    Icons.nights_stay,
                    Colors.indigo,
                  ),
                )),
                  ],
                ),
              ),
              ),

          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickMealLogDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  int _calculateCalorieTarget(profile) {
    if (profile == null) return 2000;

    final age = profile.age ?? 25;
    final weight = profile.weight ?? 70;
    final height = profile.height ?? 170;
    final gender = profile.gender ?? 'male';
    final activityLevel = profile.activityLevel ?? 'moderate';
    final goal = profile.primaryGoal ?? 'maintain';

    // Mifflin-St Jeor BMR
    double bmr = (10 * weight) + (6.25 * height) - (5 * age);
    bmr += gender == 'male' ? 5 : -161;

    // Activity multiplier
    final activityMultipliers = {
      'sedentary': 1.2,
      'lightly_active': 1.375,
      'moderately_active': 1.55,
      'very_active': 1.725,
      'extremely_active': 1.9,
    };
    final tdee = bmr * (activityMultipliers[activityLevel] ?? 1.55);

    // Goal adjustment
    double targetCalories = tdee;
    if (goal == 'weight_loss') {
      targetCalories -= 500;
    } else if (goal == 'muscle_gain') {
      targetCalories += 300;
    }

    return targetCalories.round();
  }

  int _getDayNumber(String day) {
    const days = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    return days[day.toLowerCase()] ?? 1;
  }

  Widget _buildMacroColumn(BuildContext context, String label, String value, String target, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          'of $target',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMealCard(BuildContext context, dynamic mealData, String mealType, String description, String calories, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          mealType,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(description),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              calories,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          _showMealOptions(context, mealData, mealType);
        },
      ),
    );
  }

  void _showMealOptions(BuildContext context, dynamic meal, String mealType) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$mealType • ${meal.calories} kcal',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Log as Eaten'),
              subtitle: const Text('Add to today\'s food log'),
              onTap: () {
                Navigator.pop(context);
                _logMeal(meal, mealType);
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
              title: const Text('View Details'),
              subtitle: const Text('See full recipe and nutrition'),
              onTap: () {
                Navigator.pop(context);
                _showMealDetails(context, meal, mealType);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.orange),
              title: const Text('Suggest Alternative'),
              subtitle: const Text('Get a similar meal option'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Alternative suggestion feature coming soon!'),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _logMeal(dynamic meal, String mealType) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Logging meal...'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );

      // Get today's date in correct format
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Log the meal using the API
      final success = await ref.read(nutritionNotifierProvider.notifier).logMeal(
        mealDate: today,
        mealType: mealType.toLowerCase(),
        mealId: meal.id,
        customMealName: meal.name,
        calories: meal.calories,
        proteinGrams: meal.proteinGrams,
        carbsGrams: meal.carbsGrams,
        fatGrams: meal.fatGrams,
      );

      if (!mounted) return;

      // Show result
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  success
                      ? 'Logged ${meal.name} (${meal.calories} kcal)'
                      : 'Failed to log meal. Please try again.',
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to log meal: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showMealDetails(BuildContext context, dynamic meal, String mealType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(meal.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meal type and calories
              Row(
                children: [
                  Chip(
                    label: Text(mealType),
                    avatar: const Icon(Icons.restaurant, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text('${meal.calories} kcal'),
                    backgroundColor: Colors.orange.withOpacity(0.1),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              if (meal.description != null && meal.description.isNotEmpty) ...[
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(meal.description),
                const SizedBox(height: 16),
              ],

              // Macros
              Text(
                'Macronutrients',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNutrientInfo('Protein', '${meal.proteinGrams}g', Colors.red),
                  _buildNutrientInfo('Carbs', '${meal.carbsGrams}g', Colors.blue),
                  _buildNutrientInfo('Fat', '${meal.fatGrams}g', Colors.green),
                ],
              ),
              const SizedBox(height: 16),

              // Ingredients
              if (meal.ingredients != null && meal.ingredients.isNotEmpty) ...[
                Text(
                  'Ingredients',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...meal.ingredients.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 6),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${entry.key}: ${entry.value}'),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
              ],

              // Instructions
              if (meal.instructions != null && meal.instructions.isNotEmpty) ...[
                Text(
                  'Instructions',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(meal.instructions),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _logMeal(meal, mealType);
            },
            icon: const Icon(Icons.check_circle),
            label: const Text('Log as Eaten'),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showNutritionQuestionnaire(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NutritionQuestionnaireScreen(
          onComplete: () {
            // Questionnaire completed - show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Nutrition profile saved! Generating your plan...'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeaturePreviewItem(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  void _showQuickMealLogDialog(BuildContext context) {
    final caloriesController = TextEditingController();
    final nameController = TextEditingController();
    String selectedMealType = 'snack';
    final mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Quick Meal Log', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'What did you eat?', border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: caloriesController,
                decoration: const InputDecoration(labelText: 'Estimated calories', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: mealTypes.map((type) => ChoiceChip(
                  label: Text(type[0].toUpperCase() + type.substring(1)),
                  selected: selectedMealType == type,
                  onSelected: (sel) => setModalState(() => selectedMealType = type),
                )).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/food-scanner');
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Scan Instead'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;
                        Navigator.pop(ctx);
                        final today = DateTime.now().toIso8601String().split('T')[0];
                        final calories = int.tryParse(caloriesController.text) ?? 0;
                        final success = await ref.read(nutritionNotifierProvider.notifier).logMeal(
                          mealDate: today,
                          mealType: selectedMealType,
                          customMealName: nameController.text.trim(),
                          calories: calories,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(success ? 'Logged: ${nameController.text.trim()}' : 'Failed to log meal'),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ));
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Log Meal'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRegenerateDialog(BuildContext context, WidgetRef ref) {
    // Guard: Ensure assessment is completed
    final authState = ref.read(authNotifierProvider);
    final hasAssessment = authState.profile?.nutritionPreferences != null &&
        (authState.profile!.nutritionPreferences!['questionnaire_completed'] == true) &&
        (authState.profile!.nutritionPreferences!['food_region'] != null);

    if (!hasAssessment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete your food preferences first!'),
          backgroundColor: Colors.orange,
        ),
      );
      _showNutritionQuestionnaire(context);
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Regenerate Meal Plan?'),
        content: const Text(
          'This will create a new AI-generated meal plan with different meals. '
          'Your current plan will be replaced. Generation happens in the background.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Start background generation using SSE
              final started = await ref
                  .read(generationNotifierProvider.notifier)
                  .startNutritionGeneration();

              if (started) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Regenerating meal plan in the background...'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.blue,
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationBanner(BuildContext context, GenerationTaskState task) {
    final progress = task.progress;
    final message = task.message ?? 'Generating...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: progress > 0 ? (progress / 100).clamp(0.0, 1.0) : null,
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Generating Meal Plan',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          if (progress > 0)
            Text(
              '$progress%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
  Future<void> _startGeneration(BuildContext context, WidgetRef ref) async {
    // Guard: Ensure assessment is completed before allowing generation
    final authState = ref.read(authNotifierProvider);
    final hasAssessment = authState.profile?.nutritionPreferences != null &&
        (authState.profile!.nutritionPreferences!['questionnaire_completed'] == true) &&
        (authState.profile!.nutritionPreferences!['food_region'] != null);

    if (!hasAssessment) {
      if (mounted) {
        _showNutritionQuestionnaire(context);
      }
      return;
    }

    final success = await ref.read(generationNotifierProvider.notifier).startNutritionGeneration();

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nutrition plan generation started! This may take a few minutes.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}