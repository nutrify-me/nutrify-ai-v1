import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fitness.dart';
import '../../models/workout_session.dart';
import '../../models/exercise_library.dart';
import '../../providers/workout_session_provider.dart';
import '../../providers/exercise_library_provider.dart';
import '../../providers/gamification_provider.dart';
import '../../providers/fitness_provider.dart';
import '../../services/workout_cache_service.dart';
import 'workout_summary_screen.dart';
import 'exercise_picker_screen.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final Workout workout;
  final DateTime? forDate; // Date the workout is for (defaults to today)
  final bool editMode; // Whether we're editing an existing workout
  final WorkoutSessionLocal? existingSession; // The session being edited

  const ActiveWorkoutScreen({
    super.key,
    required this.workout,
    this.forDate,
    this.editMode = false,
    this.existingSession,
  });

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  final Map<String, TextEditingController> _weightControllers = {};
  final Map<String, TextEditingController> _repsControllers = {};
  final Map<String, TextEditingController> _durationControllers = {};
  int? _expandedExerciseIndex;
  int _defaultRestSeconds = 90; // Default rest time in seconds

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.editMode && widget.existingSession != null) {
        // Load existing workout data for editing
        _loadExistingWorkout();
      } else {
        // Start new workout
        ref.read(workoutSessionProvider.notifier).startWorkout(widget.workout, forDate: widget.forDate);
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    for (final controller in _repsControllers.values) {
      controller.dispose();
    }
    for (final controller in _durationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _getWeightController(String key, double? defaultValue) {
    if (!_weightControllers.containsKey(key)) {
      _weightControllers[key] = TextEditingController(
        text: defaultValue?.toStringAsFixed(1) ?? '',
      );
    }
    return _weightControllers[key]!;
  }

  TextEditingController _getRepsController(String key, int? defaultValue) {
    if (!_repsControllers.containsKey(key)) {
      _repsControllers[key] = TextEditingController(
        text: defaultValue?.toString() ?? '',
      );
    }
    return _repsControllers[key]!;
  }

  TextEditingController _getDurationController(String key, int? defaultValue) {
    if (!_durationControllers.containsKey(key)) {
      _durationControllers[key] = TextEditingController(
        text: defaultValue?.toString() ?? '',
      );
    }
    return _durationControllers[key]!;
  }

  /// Load existing workout data for editing
  Future<void> _loadExistingWorkout() async {
    if (widget.existingSession == null) return;

    final session = widget.existingSession!;
    final sets = await WorkoutCacheService.instance.getSessionSets(session.id);

    // Start workout in edit mode with existing data
    ref.read(workoutSessionProvider.notifier).loadExistingWorkout(
      sessionId: session.id,
      workoutName: session.workoutName,
      startedAt: session.startedAt,
      sets: sets,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(workoutSessionProvider);
    final notifier = ref.read(workoutSessionProvider.notifier);
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = theme.scaffoldBackgroundColor;
    final surfaceColor = theme.colorScheme.surface;

    return PopScope(
      canPop: !sessionState.hasActiveSession,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && sessionState.hasActiveSession) {
          final shouldLeave = await _showAbandonDialog();
          if (shouldLeave && mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: surfaceColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (sessionState.hasActiveSession) {
                final shouldLeave = await _showAbandonDialog();
                if (shouldLeave && mounted) {
                  Navigator.pop(context);
                }
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.workout.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                notifier.formattedElapsedTime,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            if (sessionState.totalSets > 0)
              TextButton(
                onPressed: () => _finishWorkout(),
                child: Text(
                  'Finish',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
        body: sessionState.isLoading && sessionState.exercises.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Exercise List with Rest Timer Setting at top
                  ListView.builder(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: sessionState.isRestTimerActive ? 140 : 80,
                    ),
                    itemCount: sessionState.exercises.length + 2, // +1 for rest timer setting, +1 for add exercise button
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildRestTimerSetting(context);
                      }
                      if (index == sessionState.exercises.length + 1) {
                        return _buildAddExerciseButton(context);
                      }
                      return _buildExerciseCard(
                        context,
                        sessionState.exercises[index - 1], // Offset by 1 due to rest timer setting
                        index - 1,
                      );
                    },
                  ),

                  // Rest Timer Overlay
                  if (sessionState.isRestTimerActive)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildRestTimerOverlay(context, sessionState, notifier),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildRestTimerSetting(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _defaultRestSeconds ~/ 60;
    final seconds = _defaultRestSeconds % 60;
    final displayTime = seconds == 0
        ? '${minutes}m'
        : minutes == 0
            ? '${seconds}s'
            : '${minutes}m ${seconds}s';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Text(
            'Rest Timer',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          // Timer presets - make scrollable to prevent overflow
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTimerPreset(context, '30s', 30),
                  const SizedBox(width: 8),
                  _buildTimerPreset(context, '1m', 60),
                  const SizedBox(width: 8),
                  _buildTimerPreset(context, '1.5m', 90),
                  const SizedBox(width: 8),
                  _buildTimerPreset(context, '2m', 120),
                  const SizedBox(width: 8),
                  _buildTimerPreset(context, '3m', 180),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerPreset(BuildContext context, String label, int seconds) {
    final theme = Theme.of(context);
    final isSelected = _defaultRestSeconds == seconds;

    return GestureDetector(
      onTap: () {
        setState(() {
          _defaultRestSeconds = seconds;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildRestTimerOverlay(
    BuildContext context,
    WorkoutSessionState state,
    WorkoutSessionNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final progress = state.restTimeRemaining / state.restTimerDuration;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Rest Timer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    _buildTimerButton('-10s', () => notifier.addRestTime(-10)),
                    const SizedBox(width: 8),
                    _buildTimerButton('+10s', () => notifier.addRestTime(10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Large timer display
            Text(
              notifier.formattedRestTime,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            // Skip button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => notifier.skipRestTimer(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Skip Rest',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerButton(String label, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    BuildContext context,
    ActiveExerciseProgress exercise,
    int exerciseIndex,
  ) {
    final theme = Theme.of(context);
    final isExpanded = _expandedExerciseIndex == exerciseIndex;
    final completedSets = exercise.completedSets.length;
    final isComplete = exercise.isComplete;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () {
              setState(() {
                _expandedExerciseIndex = isExpanded ? null : exerciseIndex;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Completion indicator (only show checkmark when complete)
                  if (isComplete)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  if (isComplete) const SizedBox(width: 12),
                  // Exercise name and number
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${exercise.completedSets.where((s) => !s.isWarmup).length}/${exercise.targetSets} sets${exercise.targetReps != null ? ' • ${exercise.targetReps} reps' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Info button for non-custom exercises
                  if (!exercise.exerciseId.startsWith('custom_'))
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 20),
                      onPressed: () => _showExerciseInstructions(exercise.exerciseId, exercise.name),
                      tooltip: 'View instructions',
                      padding: const EdgeInsets.all(8),
                    ),
                  // Delete exercise button
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 22),
                    onPressed: () => _deleteExercise(exerciseIndex, exercise.name),
                    tooltip: 'Delete exercise',
                    padding: const EdgeInsets.all(8),
                  ),
                  // Sets progress
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? Colors.green.withOpacity(0.1)
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$completedSets/${exercise.targetSets}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isComplete ? Colors.green : theme.colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Previous session info
                  if (exercise.previousSession != null && exercise.previousSession!.isNotEmpty)
                    _buildPreviousSessionInfo(context, exercise),

                  // Set header row
                  _buildSetHeaderRow(context, exercise),

                  // All set rows (completed + pending input rows)
                  ...List.generate(exercise.targetSets, (setIndex) {
                    final setNumber = setIndex + 1;
                    // Check if this set is already completed
                    if (setIndex < exercise.completedSets.length) {
                      return _buildCompletedSetRow(
                        context,
                        exercise.completedSets[setIndex],
                        setNumber,
                        exercise,
                        exerciseIndex,
                        setIndex,
                      );
                    } else {
                      // Show input row for pending sets
                      return _buildSetInputRow(
                        context,
                        exerciseIndex,
                        setNumber,
                        exercise,
                      );
                    }
                  }),

                  // Add set button (always visible to allow adding more sets)
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(workoutSessionProvider.notifier).addExtraSet(exerciseIndex);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Set'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getExerciseSubtitle(ActiveExerciseProgress exercise) {
    switch (exercise.exerciseType) {
      case ExerciseType.weighted:
        return 'Weight × Reps';
      case ExerciseType.bodyweight:
        return 'Reps only';
      case ExerciseType.duration:
        return 'Timed';
      case ExerciseType.cardio:
        return 'Distance';
    }
  }

  Widget _buildPreviousSessionInfo(BuildContext context, ActiveExerciseProgress exercise) {
    final theme = Theme.of(context);
    final entries = exercise.previousSession!.take(3);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Previous: ${entries.map((e) => '${e.weightKg}kg×${e.reps}').join(', ')}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetHeaderRow(BuildContext context, ActiveExerciseProgress exercise) {
    final theme = Theme.of(context);
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('SET', style: headerStyle)),
          if (exercise.exerciseType == ExerciseType.weighted)
            Expanded(child: Center(child: Text('KG', style: headerStyle))),
          if (exercise.exerciseType == ExerciseType.duration)
            Expanded(child: Center(child: Text('TIME', style: headerStyle)))
          else
            Expanded(
              child: Center(
                child: Text(
                  exercise.exerciseType == ExerciseType.duration || exercise.exerciseType == ExerciseType.cardio
                      ? 'DURATION'
                      : 'REPS',
                  style: headerStyle,
                ),
              ),
            ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCompletedSetRow(
    BuildContext context,
    CompletedSetLocal set,
    int setNumber,
    ActiveExerciseProgress exercise,
    int exerciseIndex,
    int setIndex,
  ) {
    final theme = Theme.of(context);

    return Dismissible(
      key: Key('set_${exercise.exerciseId}_$setIndex'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        // Show confirmation dialog
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Set?'),
            content: Text(
              'Remove set $setNumber (${set.weightKg.toStringAsFixed(1)} kg × ${set.reps} reps)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (direction) {
        ref.read(workoutSessionProvider.notifier).deleteSet(
          exerciseIndex: exerciseIndex,
          setIndex: setIndex,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Set $setNumber deleted'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Set number
            SizedBox(
              width: 40,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: set.isWarmup
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    set.isWarmup ? 'W' : '$setNumber',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: set.isWarmup ? Colors.orange : Colors.green,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            // Weight (if applicable)
            if (exercise.exerciseType == ExerciseType.weighted)
              Expanded(
                child: Center(
                  child: Text(
                    set.weightKg.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (set.isPR)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.star,
                          size: 16,
                          color: Colors.amber,
                        ),
                      ),
                    Text(
                      exercise.exerciseType == ExerciseType.duration || exercise.exerciseType == ExerciseType.cardio
                          ? _formatDuration(set.durationSeconds ?? 0)
                          : '${set.reps}',
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            // Checkmark
            SizedBox(
              width: 48,
              child: Icon(Icons.check_circle, color: Colors.green, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetInputRow(
    BuildContext context,
    int exerciseIndex,
    int setNumber,
    ActiveExerciseProgress exercise,
  ) {
    final theme = Theme.of(context);
    final key = '${exerciseIndex}_$setNumber';

    // Get default values
    double? defaultWeight;
    int? defaultReps;

    if (exercise.completedSets.isNotEmpty) {
      defaultWeight = exercise.completedSets.last.weightKg;
      defaultReps = exercise.completedSets.last.reps;
    } else if (exercise.previousSession != null && exercise.previousSession!.isNotEmpty) {
      defaultWeight = exercise.previousSession!.first.weightKg;
      defaultReps = exercise.previousSession!.first.reps;
    }

    final weightController = _getWeightController(key, defaultWeight);
    final repsController = _getRepsController(key, defaultReps ?? exercise.targetReps);
    final durationController = _getDurationController(key, exercise.targetDurationSeconds);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Set number
          SizedBox(
            width: 40,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '$setNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          // Weight input (for weighted exercises)
          if (exercise.exerciseType == ExerciseType.weighted)
            Expanded(
              child: _buildNumberInput(
                controller: weightController,
                isDecimal: true,
                onChanged: (value) {},
              ),
            ),
          // Reps or Duration input
          Expanded(
            child: exercise.exerciseType == ExerciseType.duration
                ? _buildNumberInput(
                    controller: durationController,
                    suffix: 's',
                    onChanged: (value) {},
                  )
                : _buildNumberInput(
                    controller: repsController,
                    onChanged: (value) {},
                  ),
          ),
          // Complete button
          SizedBox(
            width: 48,
            child: IconButton(
              onPressed: () => _logSet(
                exerciseIndex,
                weightController,
                repsController,
                durationController,
                key,
                exercise.exerciseType,
              ),
              icon: Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.primary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    bool isDecimal = false,
    String? suffix,
    required ValueChanged<String> onChanged,
  }) {
    return Center(
      child: SizedBox(
        width: 80,
        child: TextField(
          controller: controller,
          keyboardType: isDecimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey.withOpacity(0.1),
            suffixText: suffix,
          ),
          inputFormatters: [
            isDecimal
                ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildAddExerciseButton(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(12),
      child: OutlinedButton.icon(
        onPressed: () => _showAddExerciseDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Exercise'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showAddExerciseDialog(BuildContext context) async {
    // Get current exercise IDs to exclude
    final currentState = ref.read(workoutSessionProvider);
    final excludeIds = currentState.exercises.map((e) => e.exerciseId).toList();

    // Navigate to exercise picker
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePickerScreen(
          multiSelect: false,
          excludeIds: excludeIds,
        ),
      ),
    );

    if (result != null && mounted) {
      if (result is LibraryExercise) {
        _addExerciseFromLibrary(result);
      }
    }
  }

  void _addExerciseFromLibrary(LibraryExercise exercise) {
    final notifier = ref.read(workoutSessionProvider.notifier);
    final currentState = ref.read(workoutSessionProvider);
    final type = exercise.workoutExerciseType;

    final newExercise = ActiveExerciseProgress(
      exerciseId: exercise.id,
      name: exercise.name,
      exerciseType: type,
      targetSets: 1, // Changed from 3 to 1
      targetReps: type == ExerciseType.duration || type == ExerciseType.cardio ? null : 10,
      targetDurationSeconds: type == ExerciseType.duration || type == ExerciseType.cardio ? 300 : null, // 5 minutes default
      restSeconds: 90,
    );

    // Add to provider state
    notifier.addExercise(newExercise);

    // Expand the new exercise
    setState(() {
      _expandedExerciseIndex = currentState.exercises.length;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${exercise.name}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _logSet(
    int exerciseIndex,
    TextEditingController weightController,
    TextEditingController repsController,
    TextEditingController durationController,
    String key,
    ExerciseType exerciseType,
  ) {
    double weight = 0;
    int reps = 0;
    int? duration;

    if (exerciseType == ExerciseType.weighted) {
      weight = double.tryParse(weightController.text) ?? 0;
      reps = int.tryParse(repsController.text) ?? 0;

      if (weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid weight')),
        );
        return;
      }
      if (reps <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid reps')),
        );
        return;
      }
    } else if (exerciseType == ExerciseType.bodyweight) {
      reps = int.tryParse(repsController.text) ?? 0;
      if (reps <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid reps')),
        );
        return;
      }
    } else if (exerciseType == ExerciseType.duration) {
      duration = int.tryParse(durationController.text);
      if (duration == null || duration <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid duration')),
        );
        return;
      }
    }

    final success = ref.read(workoutSessionProvider.notifier).logSet(
      exerciseIndex: exerciseIndex,
      weightKg: weight,
      reps: reps,
      durationSeconds: duration,
      customRestSeconds: _defaultRestSeconds,
    );

    if (success) {
      _weightControllers.remove(key);
      _repsControllers.remove(key);
      _durationControllers.remove(key);
      setState(() {});
      HapticFeedback.mediumImpact();
    }
  }

  Future<bool> _showAbandonDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Workout?'),
        content: const Text(
          'Are you sure you want to discard this workout? All progress will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(workoutSessionProvider.notifier).abandonWorkout();
              if (mounted) Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _finishWorkout() async {
    final summary = await ref.read(workoutSessionProvider.notifier).finishWorkout();

    if (summary != null && mounted) {
      // Refresh streak and stats after workout completion
      try {
        // Invalidate the streak provider to force refresh on dashboard
        ref.invalidate(streakProvider);

        await Future.wait<void>([
          ref.read(gamificationProvider.notifier).loadStreak(),
          ref.read(fitnessNotifierProvider.notifier).loadWeeklyStats(forceRefresh: true),
        ]);
      } catch (e) {
        // Log but don't block navigation
        debugPrint('Failed to refresh streak/stats: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutSummaryScreen(summary: summary),
          ),
        );
      }
    }
  }

  /// Show exercise instructions in a dialog
  Future<void> _showExerciseInstructions(String exerciseId, String exerciseName) async {
    // Get the exercise from library
    final libraryState = ref.read(exerciseLibraryProvider);
    final exercise = libraryState.allExercises.firstWhere(
      (e) => e.id == exerciseId,
      orElse: () => LibraryExercise(
        id: '',
        name: '',
        level: '',
        equipment: '',
        category: '',
        primaryMuscles: [],
      ),
    );

    if (exercise.id.isEmpty || exercise.instructions == null || exercise.instructions!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No instructions available for this exercise')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exerciseName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Instructions:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ...List.generate(
                exercise.instructions!.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: Text(exercise.instructions![index]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Delete an exercise with confirmation
  Future<void> _deleteExercise(int exerciseIndex, String exerciseName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Exercise?'),
        content: Text('Remove "$exerciseName" and all its sets from this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(workoutSessionProvider.notifier).removeExercise(exerciseIndex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $exerciseName'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Format duration in seconds to mm:ss format
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
