import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/exercise_library.dart';
import '../../models/workout_session.dart';
import '../../providers/exercise_library_provider.dart';

/// Screen for picking exercises from the library
class ExercisePickerScreen extends ConsumerStatefulWidget {
  final bool multiSelect;
  final List<String>? excludeIds;

  const ExercisePickerScreen({
    super.key,
    this.multiSelect = false,
    this.excludeIds,
  });

  @override
  ConsumerState<ExercisePickerScreen> createState() =>
      _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  final _searchController = TextEditingController();
  final _selectedExercises = <LibraryExercise>[];
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    // Clear any previous search/filters when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(exerciseLibraryProvider.notifier).clearFilters();
      ref.read(exerciseLibraryProvider.notifier).search('');
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(exerciseLibraryProvider);
    final theme = Theme.of(context);

    // Theme-aware colors
    final backgroundColor = theme.scaffoldBackgroundColor;
    final surfaceColor = theme.colorScheme.surface;
    final cardColor = theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.colorScheme.onSurface;
    final subtitleColor = theme.colorScheme.onSurfaceVariant;
    final borderColor = theme.dividerColor;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        foregroundColor: textColor,
        elevation: isDark ? 0 : 1,
        title: const Text('Add Exercise'),
        actions: [
          if (widget.multiSelect && _selectedExercises.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context, _selectedExercises);
              },
              child: Text(
                'Add (${_selectedExercises.length})',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateCustomExerciseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Custom'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: surfaceColor,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search exercises...',
                    hintStyle: TextStyle(color: subtitleColor),
                    prefixIcon: Icon(Icons.search, color: subtitleColor),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.clear, color: subtitleColor),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(exerciseLibraryProvider.notifier)
                                  .search('');
                            },
                          ),
                        IconButton(
                          icon: Icon(
                            Icons.filter_list,
                            color: libraryState.hasFilters
                                ? theme.colorScheme.primary
                                : subtitleColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    ref.read(exerciseLibraryProvider.notifier).search(value);
                  },
                ),

                // Filters section
                if (_showFilters) ...[
                  const SizedBox(height: 12),
                  _buildFilters(libraryState, isDark, cardColor!, subtitleColor!, textColor!),
                ],
              ],
            ),
          ),

          // Results count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: backgroundColor,
            child: Row(
              children: [
                Text(
                  '${libraryState.filteredExercises.length} exercises',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (libraryState.hasFilters)
                  TextButton(
                    onPressed: () {
                      ref.read(exerciseLibraryProvider.notifier).clearFilters();
                    },
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ),

          // Exercise list
          Expanded(
            child: libraryState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : libraryState.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: Colors.red[400]),
                            const SizedBox(height: 16),
                            Text(
                              libraryState.error!,
                              style: TextStyle(color: subtitleColor),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : libraryState.filteredExercises.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off,
                                    size: 48, color: subtitleColor),
                                const SizedBox(height: 16),
                                Text(
                                  'No exercises found',
                                  style: TextStyle(color: subtitleColor),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => _showCreateCustomExerciseDialog(context),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create custom exercise'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80), // Space for FAB
                            itemCount: libraryState.filteredExercises.length,
                            itemBuilder: (context, index) {
                              final exercise =
                                  libraryState.filteredExercises[index];

                              // Skip excluded exercises
                              if (widget.excludeIds?.contains(exercise.id) ??
                                  false) {
                                return const SizedBox.shrink();
                              }

                              return _buildExerciseItem(
                                exercise,
                                isDark,
                                textColor!,
                                subtitleColor!,
                                cardColor!,
                                borderColor!,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(
    ExerciseLibraryState state,
    bool isDark,
    Color cardColor,
    Color subtitleColor,
    Color textColor,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Category filter
        _buildFilterDropdown(
          label: 'Category',
          value: state.categoryFilter,
          items: state.categories,
          isDark: isDark,
          cardColor: cardColor,
          subtitleColor: subtitleColor,
          textColor: textColor,
          onChanged: (value) {
            ref.read(exerciseLibraryProvider.notifier).setCategoryFilter(value);
          },
        ),

        // Equipment filter
        _buildFilterDropdown(
          label: 'Equipment',
          value: state.equipmentFilter,
          items: state.equipment,
          isDark: isDark,
          cardColor: cardColor,
          subtitleColor: subtitleColor,
          textColor: textColor,
          onChanged: (value) {
            ref
                .read(exerciseLibraryProvider.notifier)
                .setEquipmentFilter(value);
          },
        ),

        // Muscle filter
        _buildFilterDropdown(
          label: 'Muscle',
          value: state.muscleFilter,
          items: state.muscles,
          isDark: isDark,
          cardColor: cardColor,
          subtitleColor: subtitleColor,
          textColor: textColor,
          onChanged: (value) {
            ref.read(exerciseLibraryProvider.notifier).setMuscleFilter(value);
          },
        ),

        // Level filter
        _buildFilterDropdown(
          label: 'Level',
          value: state.levelFilter,
          items: state.levels,
          isDark: isDark,
          cardColor: cardColor,
          subtitleColor: subtitleColor,
          textColor: textColor,
          onChanged: (value) {
            ref.read(exerciseLibraryProvider.notifier).setLevelFilter(value);
          },
        ),
      ],
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required bool isDark,
    required Color cardColor,
    required Color subtitleColor,
    required Color textColor,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: value != null
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : cardColor,
        borderRadius: BorderRadius.circular(8),
        border: value != null
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          hint: Text(
            label,
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          dropdownColor: Theme.of(context).colorScheme.surface,
          style: TextStyle(color: textColor, fontSize: 13),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('All $label', style: TextStyle(color: subtitleColor)),
            ),
            ...items.map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(_formatFilterValue(item)),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _formatFilterValue(String value) {
    return value
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Widget _buildExerciseItem(
    LibraryExercise exercise,
    bool isDark,
    Color textColor,
    Color subtitleColor,
    Color cardColor,
    Color borderColor,
  ) {
    final isSelected = _selectedExercises.contains(exercise);
    final theme = Theme.of(context);
    final isCustom = ref.read(exerciseLibraryProvider.notifier).isCustomExercise(exercise.id);

    return InkWell(
      onTap: () {
        if (widget.multiSelect) {
          setState(() {
            if (isSelected) {
              _selectedExercises.remove(exercise);
            } else {
              _selectedExercises.add(exercise);
            }
          });
        } else {
          Navigator.pop(context, exercise);
        }
      },
      onLongPress: isCustom ? () => _showDeleteCustomExerciseDialog(exercise) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Exercise type indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getTypeColor(exercise.exerciseType).withValues(alpha: isDark ? 0.2 : 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getTypeIcon(exercise.exerciseType),
                color: _getTypeColor(exercise.exerciseType),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Exercise info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          exercise.name,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Custom',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    exercise.primaryMusclesDisplay,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildTag(_getTypeLabel(exercise.exerciseType), cardColor, _getTypeColor(exercise.exerciseType)),
                      const SizedBox(width: 6),
                      _buildTag(exercise.categoryDisplay, cardColor, subtitleColor),
                      const SizedBox(width: 6),
                      _buildTag(exercise.levelDisplay, cardColor, subtitleColor),
                    ],
                  ),
                ],
              ),
            ),

            // Selection indicator
            if (widget.multiSelect)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color:
                        isSelected ? theme.colorScheme.primary : subtitleColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              )
            else
              Icon(Icons.chevron_right, color: subtitleColor),
          ],
        ),
      ),
    );
  }

  void _showDeleteCustomExerciseDialog(LibraryExercise exercise) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Custom Exercise'),
        content: Text('Are you sure you want to delete "${exercise.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(exerciseLibraryProvider.notifier)
                  .deleteCustomExercise(exercise.id);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color cardColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
        ),
      ),
    );
  }

  Color _getTypeColor(LibraryExerciseType type) {
    switch (type) {
      case LibraryExerciseType.weighted:
        return Colors.blue;
      case LibraryExerciseType.bodyweight:
        return Colors.green;
      case LibraryExerciseType.duration:
        return Colors.orange;
      case LibraryExerciseType.cardio:
        return Colors.red;
    }
  }

  IconData _getTypeIcon(LibraryExerciseType type) {
    switch (type) {
      case LibraryExerciseType.weighted:
        return Icons.fitness_center;
      case LibraryExerciseType.bodyweight:
        return Icons.accessibility_new;
      case LibraryExerciseType.duration:
        return Icons.timer;
      case LibraryExerciseType.cardio:
        return Icons.directions_run;
    }
  }

  String _getTypeLabel(LibraryExerciseType type) {
    switch (type) {
      case LibraryExerciseType.weighted:
        return 'Weighted';
      case LibraryExerciseType.bodyweight:
        return 'Bodyweight';
      case LibraryExerciseType.duration:
        return 'Timed';
      case LibraryExerciseType.cardio:
        return 'Cardio';
    }
  }

  void _showCreateCustomExerciseDialog(BuildContext context) {
    final theme = Theme.of(context);
    final nameController = TextEditingController();
    LibraryExerciseType? selectedType = LibraryExerciseType.weighted;
    String selectedMuscle = 'full body';

    final muscles = [
      'full body',
      'chest', 'back', 'shoulders', 'biceps', 'triceps',
      'forearms', 'quadriceps', 'hamstrings', 'glutes', 'calves',
      'abdominals', 'obliques', 'lower back', 'traps', 'lats',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Create Custom Exercise',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Exercise name
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Exercise Name',
                        hintText: 'e.g., Cable Crossover',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Exercise type
                    const Text(
                      'Exercise Type',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: LibraryExerciseType.values.map((type) {
                        final isSelected = selectedType == type;
                        return ChoiceChip(
                          label: Text(_getTypeLabel(type)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() => selectedType = type);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Primary muscle
                    const Text(
                      'Primary Muscle',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: muscles.map((muscle) {
                        final isSelected = selectedMuscle == muscle;
                        return ChoiceChip(
                          label: Text(_formatFilterValue(muscle)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() => selectedMuscle = muscle);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Create button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          if (nameController.text.trim().isNotEmpty) {
                            // Determine category and equipment based on selectedType
                            String category;
                            String equipment;

                            switch (selectedType!) {
                              case LibraryExerciseType.cardio:
                                category = 'cardio';
                                equipment = 'other';
                                break;
                              case LibraryExerciseType.duration:
                                category = 'stretching';
                                equipment = 'body only';
                                break;
                              case LibraryExerciseType.bodyweight:
                                category = 'strength';
                                equipment = 'body only';
                                break;
                              case LibraryExerciseType.weighted:
                                category = 'strength';
                                equipment = 'other';
                                break;
                            }

                            final customExercise = LibraryExercise(
                              id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                              name: nameController.text.trim(),
                              level: 'intermediate',
                              equipment: equipment,
                              category: category,
                              primaryMuscles: [selectedMuscle],
                            );
                            // Save to local database via provider
                            await ref.read(exerciseLibraryProvider.notifier)
                                .addCustomExercise(customExercise);
                            if (mounted) {
                              Navigator.pop(context); // Close dialog
                              Navigator.pop(this.context, customExercise); // Return exercise
                            }
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Create & Add'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }


}
