import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../models/workout_session.dart';
import '../models/fitness.dart';
import '../services/api_service.dart';
import '../services/workout_cache_service.dart';
import '../services/sync_service.dart';
import 'auth_provider.dart';

final _logger = Logger();
final _uuid = Uuid();

/// UUID validation regex
final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isValidUuid(String value) => _uuidRegex.hasMatch(value);

/// Pending set to be synced with backend
class PendingSet {
  final String exerciseId;
  final String exerciseName;
  final int setNumber;
  final double weightKg;
  final int reps;
  final bool isWarmup;
  final int restSeconds;
  final DateTime completedAt;

  PendingSet({
    required this.exerciseId,
    required this.exerciseName,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.isWarmup,
    required this.restSeconds,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'exercise_name': exerciseName,
    'set_number': setNumber,
    'weight_kg': weightKg,
    'reps': reps,
    'is_warmup': isWarmup,
    'rest_seconds': restSeconds,
  };
}

/// State for the active workout session
class WorkoutSessionState {
  final WorkoutSession? activeSession;
  final List<ActiveExerciseProgress> exercises;
  final int currentExerciseIndex;
  final bool isLoading;
  final bool isSyncing;
  final String? error;

  // Rest timer state
  final int restTimeRemaining;
  final int restTimerDuration;
  final bool isRestTimerActive;

  // Elapsed workout time
  final int elapsedSeconds;

  // Pending sets to sync (local-first)
  final List<PendingSet> pendingSets;

  // Edit mode flag
  final bool isEditMode;

  const WorkoutSessionState({
    this.activeSession,
    this.exercises = const [],
    this.currentExerciseIndex = 0,
    this.isLoading = false,
    this.isSyncing = false,
    this.error,
    this.restTimeRemaining = 0,
    this.restTimerDuration = 90,
    this.isRestTimerActive = false,
    this.elapsedSeconds = 0,
    this.pendingSets = const [],
    this.isEditMode = false,
  });

  WorkoutSessionState copyWith({
    WorkoutSession? activeSession,
    List<ActiveExerciseProgress>? exercises,
    int? currentExerciseIndex,
    bool? isLoading,
    bool? isSyncing,
    String? error,
    int? restTimeRemaining,
    int? restTimerDuration,
    bool? isRestTimerActive,
    int? elapsedSeconds,
    List<PendingSet>? pendingSets,
    bool? isEditMode,
  }) {
    return WorkoutSessionState(
      activeSession: activeSession ?? this.activeSession,
      exercises: exercises ?? this.exercises,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error,
      restTimeRemaining: restTimeRemaining ?? this.restTimeRemaining,
      restTimerDuration: restTimerDuration ?? this.restTimerDuration,
      isRestTimerActive: isRestTimerActive ?? this.isRestTimerActive,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      pendingSets: pendingSets ?? this.pendingSets,
      isEditMode: isEditMode ?? this.isEditMode,
    );
  }

  bool get hasActiveSession => activeSession != null && activeSession!.isActive;

  ActiveExerciseProgress? get currentExercise =>
      exercises.isNotEmpty && currentExerciseIndex < exercises.length
          ? exercises[currentExerciseIndex]
          : null;

  int get totalVolume {
    int volume = 0;
    for (final exercise in exercises) {
      for (final set in exercise.completedSets) {
        if (!set.isWarmup) {
          volume += set.volume;
        }
      }
    }
    return volume;
  }

  int get totalSets {
    int sets = 0;
    for (final exercise in exercises) {
      sets += exercise.completedSets.where((s) => !s.isWarmup).length;
    }
    return sets;
  }

  int get prsThisSession {
    int prs = 0;
    for (final exercise in exercises) {
      prs += exercise.completedSets.where((s) => s.isPR).length;
    }
    return prs;
  }
}

/// Notifier for managing workout sessions with local-first approach
class WorkoutSessionNotifier extends StateNotifier<WorkoutSessionState> {
  final ApiService _apiService;
  final WorkoutCacheService _workoutCache = WorkoutCacheService.instance;
  final SyncService _syncService = SyncService();
  Timer? _restTimer;
  Timer? _elapsedTimer;

  WorkoutSessionNotifier(this._apiService) : super(const WorkoutSessionState()) {
    // Attempt to restore saved session on init
    _attemptSessionRestore();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  /// Attempt to restore a saved session from local storage
  Future<void> _attemptSessionRestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionData = prefs.getString('saved_workout_session');

      if (sessionData != null) {
        final Map<String, dynamic> data = json.decode(sessionData);
        final savedTimestamp = data['savedAt'] as int?;

        if (savedTimestamp != null) {
          final age = DateTime.now().millisecondsSinceEpoch - savedTimestamp;
          const twentyFourHours = 24 * 60 * 60 * 1000;

          // Only restore if less than 24 hours old
          if (age < twentyFourHours) {
            await restoreSession(data);
            _logger.d('Restored workout session from ${(age / 1000 / 60).toStringAsFixed(0)} minutes ago');
            return;
          } else {
            // Session too old, clear it
            await prefs.remove('saved_workout_session');
            _logger.d('Cleared old workout session (age: ${(age / 1000 / 60 / 60).toStringAsFixed(1)} hours)');
          }
        }
      }
    } catch (e) {
      _logger.w('Failed to restore session: $e');
      // Clear corrupted data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_workout_session');
    }
  }

  /// Save current session to local storage
  Future<void> _saveSession() async {
    if (state.activeSession == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionData = {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'sessionId': state.activeSession!.id,
        'workoutName': state.activeSession!.workoutName,
        'elapsedSeconds': state.elapsedSeconds,
        'exercises': state.exercises.map((e) => {
          'exerciseId': e.exerciseId,
          'name': e.name,
          'targetSets': e.targetSets,
          'targetReps': e.targetReps,
          'restSeconds': e.restSeconds,
          'exerciseType': e.exerciseType.name,
          'completedSets': e.completedSets.map((s) => {
            'setNumber': s.setNumber,
            'weightKg': s.weightKg,
            'reps': s.reps,
            'isWarmup': s.isWarmup,
          }).toList(),
        }).toList(),
      };

      await prefs.setString('saved_workout_session', json.encode(sessionData));
    } catch (e) {
      _logger.w('Failed to save session: $e');
    }
  }

  /// Restore session from saved data
  Future<void> restoreSession(Map<String, dynamic> data) async {
    try {
      final sessionId = data['sessionId'] as String;
      final workoutName = data['workoutName'] as String;
      final elapsedSeconds = data['elapsedSeconds'] as int? ?? 0;
      final exercisesData = data['exercises'] as List? ?? [];

      // Recreate session object
      final session = WorkoutSession(
        id: sessionId,
        userId: '', // Will be set by backend
        workoutName: workoutName,
        startedAt: DateTime.now().subtract(Duration(seconds: elapsedSeconds)),
        status: 'active',
        totalVolume: 0,
        durationSeconds: elapsedSeconds,
        sets: [],
      );

      // Recreate exercises
      final exercises = exercisesData.map((e) {
        final completedSetsData = e['completedSets'] as List? ?? [];
        final completedSets = completedSetsData.map((s) => CompletedSetLocal(
          setNumber: s['setNumber'] as int,
          weightKg: (s['weightKg'] as num).toDouble(),
          reps: s['reps'] as int,
          isWarmup: s['isWarmup'] as bool? ?? false,
          isPR: false,
        )).toList();

        return ActiveExerciseProgress(
          exerciseId: e['exerciseId'] as String,
          name: e['name'] as String,
          targetSets: e['targetSets'] as int,
          targetReps: e['targetReps'] as int?,
          restSeconds: e['restSeconds'] as int?,
          exerciseType: ExerciseType.values.firstWhere(
            (t) => t.name == e['exerciseType'],
            orElse: () => ExerciseType.weighted,
          ),
          completedSets: completedSets,
        );
      }).toList();

      state = state.copyWith(
        activeSession: session,
        exercises: exercises,
        elapsedSeconds: elapsedSeconds,
      );

      _startElapsedTimer();
    } catch (e) {
      _logger.e('Failed to restore session from data: $e');
      throw e;
    }
  }

  /// Clear saved session from local storage
  Future<void> _clearSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_workout_session');
    } catch (e) {
      _logger.w('Failed to clear saved session: $e');
    }
  }

  /// Start a new workout session
  Future<bool> startWorkout(Workout workout, {DateTime? forDate}) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      // Validation 1: Only allow workouts for TODAY
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      if (forDate != null) {
        final targetDate = DateTime(forDate.year, forDate.month, forDate.day);

        // Prevent future workouts
        if (targetDate.isAfter(todayDate)) {
          throw Exception('Cannot start workout for future dates. Please select today\'s workout.');
        }

        // Prevent past workouts
        if (targetDate.isBefore(todayDate)) {
          throw Exception('Cannot start workout for past dates. Workouts can only be started today.');
        }
      }

      // Validation 2: Check workout limit (max 2 per day)
      final workoutCount = await _workoutCache.countWorkoutsForDate(todayDate);
      if (workoutCount >= 2) {
        throw Exception('Cannot start more than 2 workouts per day. You have already completed $workoutCount workouts today.');
      }

      _logger.d('Starting workout: id=${workout.id}, name=${workout.name}');
      _logger.d('Workout exercises count: ${workout.exercises.length}');
      _logger.d('Workouts completed today: $workoutCount/2');

      // Only send workout_id if it's a valid UUID (not a quick start placeholder)
      final bool isValidUuid = _isValidUuid(workout.id);

      // Start session on backend (single API call)
      final session = await _apiService.startWorkoutSession(
        workoutId: isValidUuid ? workout.id : null,
        workoutName: workout.name,
      );
      _logger.d('Session started successfully: ${session.id}');

      // Initialize exercise progress from workout (no API calls here!)
      final exercises = workout.exercises.map((e) {
        return ActiveExerciseProgress(
          exerciseId: e.id,
          name: e.name,
          targetSets: e.sets ?? 3,
          targetReps: e.reps,
          restSeconds: e.restTimeSeconds ?? 90,
        );
      }).toList();

      state = state.copyWith(
        activeSession: session,
        exercises: exercises,
        currentExerciseIndex: 0,
        isLoading: false,
        elapsedSeconds: 0,
        pendingSets: [],
      );

      // Start elapsed timer
      _startElapsedTimer();

      // Save session to local storage
      await _saveSession();

      // Load exercise history in background (non-blocking)
      _loadExerciseHistoryInBackground(exercises);

      return true;
    } catch (e) {
      _logger.e('Failed to start workout: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Load an existing workout session for editing
  void loadExistingWorkout({
    required String sessionId,
    required String workoutName,
    required DateTime startedAt,
    required List<ExerciseSetLocal> sets,
  }) {
    try {
      // Create a mock session object for the UI
      final session = WorkoutSession(
        id: sessionId,
        userId: '', // Will be set properly when saving
        workoutId: null,
        workoutName: workoutName,
        startedAt: startedAt,
        completedAt: null,
        status: 'active',
        totalVolume: 0, // Will be recalculated
        durationSeconds: 0, // Will be updated when saving
        sets: [],
      );

      // Build exercise progress from existing sets
      // Group sets by exercise
      final exerciseMap = <String, List<ExerciseSetLocal>>{};
      for (final set in sets) {
        if (!exerciseMap.containsKey(set.exerciseName)) {
          exerciseMap[set.exerciseName] = [];
        }
        exerciseMap[set.exerciseName]!.add(set);
      }

      // Create ActiveExerciseProgress for each exercise
      final exercises = exerciseMap.entries.map((entry) {
        final exerciseSets = entry.value;
        return ActiveExerciseProgress(
          exerciseId: exerciseSets.first.exerciseId ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
          name: entry.key,
          targetSets: exerciseSets.length,
          targetReps: exerciseSets.first.reps,
          restSeconds: exerciseSets.first.restSeconds,
          completedSets: exerciseSets.map((s) => CompletedSetLocal(
            id: s.id,
            setNumber: s.setNumber,
            weightKg: s.weightKg,
            reps: s.reps,
            isWarmup: s.isWarmup,
            isPR: s.isPR,
            completedAt: s.completedAt,
          )).toList(),
        );
      }).toList();

      state = state.copyWith(
        activeSession: session,
        exercises: exercises,
        currentExerciseIndex: 0,
        isLoading: false,
        elapsedSeconds: 0,
        pendingSets: [],
        isEditMode: true, // Flag to indicate we're editing
      );

      _logger.i('Loaded existing workout for editing: $sessionId with ${sets.length} sets');
    } catch (e) {
      _logger.e('Failed to load existing workout: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load exercise history in background without blocking UI
  Future<void> _loadExerciseHistoryInBackground(List<ActiveExerciseProgress> exercises) async {
    for (int i = 0; i < exercises.length; i++) {
      // Check if state is still valid (session not abandoned)
      if (state.activeSession == null) return;

      try {
        final history = await _apiService.getExerciseHistory(exercises[i].name);
        if (history.entries.isNotEmpty && state.exercises.length > i) {
          final updatedExercises = List<ActiveExerciseProgress>.from(state.exercises);
          updatedExercises[i] = updatedExercises[i].copyWith(
            previousSession: history.entries.take(5).toList(),
          );
          state = state.copyWith(exercises: updatedExercises);
        }
      } catch (e) {
        _logger.d('No history for ${exercises[i].name}');
      }

      // Small delay between calls to not overwhelm the server
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Start a custom workout (not from a plan)
  Future<bool> startCustomWorkout(String workoutName, List<Exercise> exercises) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final session = await _apiService.startWorkoutSession(
        workoutName: workoutName,
      );

      final exerciseProgress = exercises.map((e) {
        return ActiveExerciseProgress(
          exerciseId: e.id,
          name: e.name,
          targetSets: e.sets ?? 3,
          targetReps: e.reps,
          restSeconds: e.restTimeSeconds ?? 90,
        );
      }).toList();

      state = state.copyWith(
        activeSession: session,
        exercises: exerciseProgress,
        currentExerciseIndex: 0,
        isLoading: false,
        elapsedSeconds: 0,
        pendingSets: [],
      );

      _startElapsedTimer();

      return true;
    } catch (e) {
      _logger.e('Failed to start custom workout: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Log a completed set - LOCAL FIRST, no network call
  bool logSet({
    required int exerciseIndex,
    double weightKg = 0,
    int reps = 0,
    int? durationSeconds,
    bool isWarmup = false,
    int? customRestSeconds, // Custom rest time from user setting
  }) {
    if (state.activeSession == null) return false;

    try {
      final exercise = state.exercises[exerciseIndex];
      final setNumber = exercise.completedSets.length + 1;
      final restSeconds = customRestSeconds ?? exercise.restSeconds ?? 90;

      // Create local set immediately (no network)
      final completedSet = CompletedSetLocal(
        setNumber: setNumber,
        weightKg: weightKg,
        reps: reps,
        durationSeconds: durationSeconds,
        isWarmup: isWarmup,
        isPR: false, // Will be determined by backend on sync
      );

      // Add to pending sets for later sync
      final pendingSet = PendingSet(
        exerciseId: exercise.exerciseId,
        exerciseName: exercise.name,
        setNumber: setNumber,
        weightKg: weightKg,
        reps: reps,
        isWarmup: isWarmup,
        restSeconds: restSeconds,
        completedAt: DateTime.now(),
      );

      // Update exercise progress immediately
      final updatedExercises = List<ActiveExerciseProgress>.from(state.exercises);
      updatedExercises[exerciseIndex] = exercise.copyWith(
        completedSets: [...exercise.completedSets, completedSet],
      );

      state = state.copyWith(
        exercises: updatedExercises,
        pendingSets: [...state.pendingSets, pendingSet],
      );

      // Save session after logging set
      _saveSession();

      // Start rest timer if not a warmup
      if (!isWarmup) {
        startRestTimer(restSeconds);
      }

      return true;
    } catch (e) {
      _logger.e('Failed to log set locally: $e');
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Add a new exercise to the current workout
  void addExercise(ActiveExerciseProgress exercise) {
    if (state.activeSession == null) return;

    state = state.copyWith(
      exercises: [...state.exercises, exercise],
    );

    // Save session after adding exercise
    _saveSession();
  }

  /// Remove an exercise from the current workout
  void removeExercise(int exerciseIndex) {
    if (state.activeSession == null) return;
    if (exerciseIndex >= state.exercises.length) return;

    final exercise = state.exercises[exerciseIndex];
    final updatedExercises = List<ActiveExerciseProgress>.from(state.exercises);
    updatedExercises.removeAt(exerciseIndex);

    // Remove all pending sets for this exercise
    final updatedPendingSets = state.pendingSets.where((pending) {
      return pending.exerciseId != exercise.exerciseId;
    }).toList();

    state = state.copyWith(
      exercises: updatedExercises,
      pendingSets: updatedPendingSets,
    );

    // Save session after removing exercise
    _saveSession();

    _logger.d('Removed exercise: ${exercise.name}');
  }

  /// Delete a completed set from an exercise
  void deleteSet({
    required int exerciseIndex,
    required int setIndex,
  }) {
    if (state.activeSession == null) return;
    if (exerciseIndex >= state.exercises.length) return;

    final exercise = state.exercises[exerciseIndex];
    if (setIndex >= exercise.completedSets.length) return;

    // Remove the set from completed sets
    final updatedSets = List<CompletedSetLocal>.from(exercise.completedSets);
    final removedSet = updatedSets.removeAt(setIndex);

    // Renumber remaining sets
    final renumberedSets = updatedSets.asMap().entries.map((entry) {
      return entry.value.copyWith(setNumber: entry.key + 1);
    }).toList();

    // Update exercise - decrease targetSets to prevent showing extra input rows
    final updatedExercises = List<ActiveExerciseProgress>.from(state.exercises);
    updatedExercises[exerciseIndex] = exercise.copyWith(
      completedSets: renumberedSets,
      targetSets: exercise.targetSets - 1, // Fix: Decrease target count
    );

    // Remove from pending sets if it hasn't been synced yet
    final updatedPendingSets = state.pendingSets.where((pending) {
      return !(pending.exerciseId == exercise.exerciseId &&
          pending.setNumber == removedSet.setNumber);
    }).toList();

    state = state.copyWith(
      exercises: updatedExercises,
      pendingSets: updatedPendingSets,
    );

    // Save session after deleting set
    _saveSession();

    _logger.d('Deleted set ${setIndex + 1} from ${exercise.name}, new target: ${exercise.targetSets - 1}');
  }

  /// Start the rest timer
  void startRestTimer(int seconds) {
    _restTimer?.cancel();

    state = state.copyWith(
      restTimeRemaining: seconds,
      restTimerDuration: seconds,
      isRestTimerActive: true,
    );

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.restTimeRemaining > 0) {
        state = state.copyWith(restTimeRemaining: state.restTimeRemaining - 1);
      } else {
        timer.cancel();
        state = state.copyWith(isRestTimerActive: false);
      }
    });
  }

  /// Skip the rest timer
  void skipRestTimer() {
    _restTimer?.cancel();
    state = state.copyWith(
      restTimeRemaining: 0,
      isRestTimerActive: false,
    );
  }

  /// Add 30 seconds to rest timer
  void addRestTime(int seconds) {
    if (state.isRestTimerActive) {
      state = state.copyWith(
        restTimeRemaining: state.restTimeRemaining + seconds,
      );
    }
  }

  /// Set the current exercise index
  void setCurrentExercise(int index) {
    if (index >= 0 && index < state.exercises.length) {
      state = state.copyWith(currentExerciseIndex: index);
    }
  }

  /// Move to the next exercise
  void nextExercise() {
    if (state.currentExerciseIndex < state.exercises.length - 1) {
      state = state.copyWith(currentExerciseIndex: state.currentExerciseIndex + 1);
    }
  }

  /// Move to the previous exercise
  void previousExercise() {
    if (state.currentExerciseIndex > 0) {
      state = state.copyWith(currentExerciseIndex: state.currentExerciseIndex - 1);
    }
  }

  /// Add an extra set to an exercise
  void addExtraSet(int exerciseIndex) {
    if (exerciseIndex >= 0 && exerciseIndex < state.exercises.length) {
      final updatedExercises = List<ActiveExerciseProgress>.from(state.exercises);
      updatedExercises[exerciseIndex] = state.exercises[exerciseIndex].copyWith(
        targetSets: state.exercises[exerciseIndex].targetSets + 1,
      );
      state = state.copyWith(exercises: updatedExercises);
    }
  }

  /// Complete the workout session - saves locally and syncs in background
  Future<WorkoutSessionSummary?> finishWorkout({String? notes}) async {
    if (state.activeSession == null) return null;

    try {
      state = state.copyWith(isLoading: true, error: null);

      final session = state.activeSession!;
      final completedAt = DateTime.now();
      final durationSeconds = state.elapsedSeconds;

      // Calculate total volume from all completed sets
      int totalVolume = 0;
      for (final exercise in state.exercises) {
        for (final set in exercise.completedSets) {
          if (!set.isWarmup) {
            totalVolume += (set.weightKg * set.reps).toInt();
          }
        }
      }

      // Convert all completed sets to ExerciseSetLocal format
      final allSets = <ExerciseSetLocal>[];
      for (final exercise in state.exercises) {
        for (final set in exercise.completedSets) {
          allSets.add(ExerciseSetLocal(
            id: set.id ?? _uuid.v4(), // Use existing ID in edit mode, or generate new
            sessionId: session.id,
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.name,
            setNumber: set.setNumber,
            weightKg: set.weightKg,
            reps: set.reps,
            isWarmup: set.isWarmup,
            restSeconds: exercise.restSeconds ?? 90,
            completedAt: set.completedAt ?? DateTime.now(),
            notes: null,
            syncStatus: 'pending',
            isPR: false, // Will be determined by backend after sync
          ));
        }
      }

      // Save or update in local SQLite database (instant!)
      if (state.isEditMode) {
        // Update existing workout
        await _workoutCache.updateWorkoutSession(
          sessionId: session.id,
          workoutName: session.workoutName,
          durationSeconds: durationSeconds,
          notes: notes,
          sets: allSets,
        );
        _logger.i('Updated workout ${session.id} in local DB with ${allSets.length} sets');
      } else {
        // Create new workout
        await _workoutCache.saveWorkoutSession(
          sessionId: session.id,
          workoutName: session.workoutName,
          workoutId: session.workoutId,
          startedAt: session.startedAt,
          completedAt: completedAt,
          status: 'completed',
          totalVolume: totalVolume,
          durationSeconds: durationSeconds,
          notes: notes,
          sets: allSets,
        );
        _logger.i('Saved new workout ${session.id} to local DB with ${allSets.length} sets');
      }

      // Get summary from local database and convert to WorkoutSessionSummary
      final summaryData = await _workoutCache.getSessionSummary(session.id);
      WorkoutSessionSummary? summary;

      if (summaryData != null) {
        summary = WorkoutSessionSummary(
          id: summaryData['id'],
          workoutName: summaryData['workout_name'],
          startedAt: DateTime.parse(summaryData['started_at']),
          completedAt: DateTime.parse(summaryData['completed_at']),
          durationSeconds: summaryData['duration_seconds'],
          totalVolume: summaryData['total_volume'],
          totalSets: summaryData['total_sets'],
          exercisesCompleted: summaryData['exercises_completed'],
          newPRs: (summaryData['new_prs'] as List).cast<Map<String, dynamic>>(),
        );
      }

      // Queue background sync (non-blocking)
      _syncService.queueWorkoutSync(session.id);
      _logger.d('Queued workout ${session.id} for background sync');

      _restTimer?.cancel();
      _elapsedTimer?.cancel();

      // Clear saved session from SharedPreferences
      await _clearSavedSession();

      state = const WorkoutSessionState(); // Reset state

      return summary;
    } catch (e) {
      _logger.e('Failed to finish workout: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return null;
    }
  }

  /// Abandon the workout session
  Future<bool> abandonWorkout() async {
    if (state.activeSession == null) return false;

    try {
      await _apiService.abandonWorkoutSession(state.activeSession!.id);

      _restTimer?.cancel();
      _elapsedTimer?.cancel();

      // Clear saved session
      await _clearSavedSession();

      state = const WorkoutSessionState(); // Reset state

      return true;
    } catch (e) {
      _logger.e('Failed to abandon workout: $e');
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Check and restore active session on app start
  Future<void> checkForActiveSession() async {
    try {
      final session = await _apiService.getActiveWorkoutSession();
      if (session != null && session.isActive) {
        // Restore session
        state = state.copyWith(
          activeSession: session,
          elapsedSeconds: session.durationSeconds,
        );
        _startElapsedTimer();
      }
    } catch (e) {
      _logger.d('No active session found');
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  /// Format elapsed time as MM:SS or HH:MM:SS
  String get formattedElapsedTime {
    final hours = state.elapsedSeconds ~/ 3600;
    final minutes = (state.elapsedSeconds % 3600) ~/ 60;
    final seconds = state.elapsedSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format rest time as M:SS
  String get formattedRestTime {
    final minutes = state.restTimeRemaining ~/ 60;
    final seconds = state.restTimeRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Provider for workout session state
final workoutSessionProvider = StateNotifierProvider<WorkoutSessionNotifier, WorkoutSessionState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return WorkoutSessionNotifier(apiService);
});

/// Provider for workout history
final workoutHistoryProvider = FutureProvider<List<WorkoutSession>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getWorkoutSessionHistory();
});

/// Provider for personal records
final personalRecordsProvider = FutureProvider<List<PersonalRecord>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getPersonalRecords();
});

/// Provider for exercise history
final exerciseHistoryProvider = FutureProvider.family<ExerciseHistory, String>((ref, exerciseName) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getExerciseHistory(exerciseName);
});
