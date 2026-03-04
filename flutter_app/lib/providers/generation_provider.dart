import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

final _logger = Logger();

/// Generation type enum
enum GenerationType {
  nutrition,
  fitness,
}

/// Status of a generation task
enum GenerationStatus {
  idle,
  pending,
  inProgress,
  completed,
  failed,
}

/// State for a single generation task
class GenerationTaskState {
  final String? taskId;
  final GenerationType type;
  final GenerationStatus status;
  final int progress;
  final String? message;
  final String? resultId;
  final String? error;

  const GenerationTaskState({
    this.taskId,
    required this.type,
    this.status = GenerationStatus.idle,
    this.progress = 0,
    this.message,
    this.resultId,
    this.error,
  });

  GenerationTaskState copyWith({
    String? taskId,
    GenerationType? type,
    GenerationStatus? status,
    int? progress,
    String? message,
    String? resultId,
    String? error,
  }) {
    return GenerationTaskState(
      taskId: taskId ?? this.taskId,
      type: type ?? this.type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message,
      resultId: resultId ?? this.resultId,
      error: error,
    );
  }

  bool get isActive => status == GenerationStatus.pending || status == GenerationStatus.inProgress;
}

/// Overall state for all generation tasks
class GenerationState {
  final GenerationTaskState? nutritionTask;
  final GenerationTaskState? fitnessTask;

  const GenerationState({
    this.nutritionTask,
    this.fitnessTask,
  });

  GenerationState copyWith({
    GenerationTaskState? nutritionTask,
    GenerationTaskState? fitnessTask,
  }) {
    return GenerationState(
      nutritionTask: nutritionTask ?? this.nutritionTask,
      fitnessTask: fitnessTask ?? this.fitnessTask,
    );
  }

  bool get hasActiveNutritionTask => nutritionTask?.isActive ?? false;
  bool get hasActiveFitnessTask => fitnessTask?.isActive ?? false;
  bool get hasAnyActiveTask => hasActiveNutritionTask || hasActiveFitnessTask;
}

/// Notifier for managing generation tasks
class GenerationNotifier extends StateNotifier<GenerationState> {
  final ApiService _apiService;
  StreamSubscription? _nutritionSubscription;
  StreamSubscription? _fitnessSubscription;

  // Callbacks for when generation completes
  void Function(String resultId)? onNutritionComplete;
  void Function(String resultId)? onFitnessComplete;
  void Function(String error)? onNutritionError;
  void Function(String error)? onFitnessError;

  GenerationNotifier(this._apiService) : super(const GenerationState());

  @override
  void dispose() {
    _nutritionSubscription?.cancel();
    _fitnessSubscription?.cancel();
    super.dispose();
  }

  /// Start nutrition plan generation in background
  Future<bool> startNutritionGeneration() async {
    if (state.hasActiveNutritionTask) {
      _logger.d('Nutrition generation already in progress');
      return false;
    }

    try {
      final response = await _apiService.startNutritionPlanGeneration();
      final taskId = response['task_id'] as String;
      final statusStr = response['status'] as String;

      _logger.d('Started nutrition generation with task ID: $taskId');

      state = state.copyWith(
        nutritionTask: GenerationTaskState(
          taskId: taskId,
          type: GenerationType.nutrition,
          status: _parseStatus(statusStr),
          message: response['message'] as String?,
        ),
      );

      // Start listening to SSE stream
      _startNutritionStream(taskId);

      return true;
    } catch (e) {
      _logger.e('Failed to start nutrition generation: $e');
      state = state.copyWith(
        nutritionTask: GenerationTaskState(
          type: GenerationType.nutrition,
          status: GenerationStatus.failed,
          error: e.toString(),
        ),
      );
      return false;
    }
  }

  /// Start fitness plan generation in background
  Future<bool> startFitnessGeneration() async {
    if (state.hasActiveFitnessTask) {
      _logger.d('Fitness generation already in progress');
      return false;
    }

    try {
      final response = await _apiService.startFitnessPlanGeneration();
      final taskId = response['task_id'] as String;
      final statusStr = response['status'] as String;

      _logger.d('Started fitness generation with task ID: $taskId');

      state = state.copyWith(
        fitnessTask: GenerationTaskState(
          taskId: taskId,
          type: GenerationType.fitness,
          status: _parseStatus(statusStr),
          message: response['message'] as String?,
        ),
      );

      // Start listening to SSE stream
      _startFitnessStream(taskId);

      return true;
    } catch (e) {
      _logger.e('Failed to start fitness generation: $e');
      state = state.copyWith(
        fitnessTask: GenerationTaskState(
          type: GenerationType.fitness,
          status: GenerationStatus.failed,
          error: e.toString(),
        ),
      );
      return false;
    }
  }

  void _startNutritionStream(String taskId) {
    _nutritionSubscription?.cancel();
    _nutritionSubscription = _apiService
        .streamNutritionGenerationStatus(taskId)
        .listen(
      (event) {
        _handleNutritionEvent(event);
      },
      onError: (error) {
        _logger.e('Nutrition SSE stream error: $error');
        state = state.copyWith(
          nutritionTask: state.nutritionTask?.copyWith(
            status: GenerationStatus.failed,
            error: error.toString(),
          ),
        );
        onNutritionError?.call(error.toString());
      },
    );
  }

  void _startFitnessStream(String taskId) {
    _fitnessSubscription?.cancel();
    _fitnessSubscription = _apiService
        .streamFitnessGenerationStatus(taskId)
        .listen(
      (event) {
        _handleFitnessEvent(event);
      },
      onError: (error) {
        _logger.e('Fitness SSE stream error: $error');
        state = state.copyWith(
          fitnessTask: state.fitnessTask?.copyWith(
            status: GenerationStatus.failed,
            error: error.toString(),
          ),
        );
        onFitnessError?.call(error.toString());
      },
    );
  }

  void _handleNutritionEvent(GenerationEvent event) {
    _logger.d('Nutrition generation event: ${event.event} - ${event.status}');

    final newTask = state.nutritionTask?.copyWith(
      status: _parseStatus(event.status ?? 'pending'),
      progress: event.progress,
      message: event.message,
      resultId: event.resultId,
      error: event.error,
    ) ?? GenerationTaskState(
      type: GenerationType.nutrition,
      status: _parseStatus(event.status ?? 'pending'),
      progress: event.progress,
      message: event.message,
      resultId: event.resultId,
      error: event.error,
    );

    state = state.copyWith(nutritionTask: newTask);

    // Handle completion
    if (event.isCompleted && event.resultId != null) {
      _nutritionSubscription?.cancel();
      onNutritionComplete?.call(event.resultId!);
    } else if (event.isFailed) {
      _nutritionSubscription?.cancel();
      onNutritionError?.call(event.error ?? 'Generation failed');
    }
  }

  void _handleFitnessEvent(GenerationEvent event) {
    _logger.d('Fitness generation event: ${event.event} - ${event.status}');

    final newTask = state.fitnessTask?.copyWith(
      status: _parseStatus(event.status ?? 'pending'),
      progress: event.progress,
      message: event.message,
      resultId: event.resultId,
      error: event.error,
    ) ?? GenerationTaskState(
      type: GenerationType.fitness,
      status: _parseStatus(event.status ?? 'pending'),
      progress: event.progress,
      message: event.message,
      resultId: event.resultId,
      error: event.error,
    );

    state = state.copyWith(fitnessTask: newTask);

    // Handle completion
    if (event.isCompleted && event.resultId != null) {
      _fitnessSubscription?.cancel();
      onFitnessComplete?.call(event.resultId!);
    } else if (event.isFailed) {
      _fitnessSubscription?.cancel();
      onFitnessError?.call(event.error ?? 'Generation failed');
    }
  }

  GenerationStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return GenerationStatus.pending;
      case 'in_progress':
        return GenerationStatus.inProgress;
      case 'completed':
        return GenerationStatus.completed;
      case 'failed':
        return GenerationStatus.failed;
      default:
        return GenerationStatus.idle;
    }
  }

  /// Clear nutrition task state
  void clearNutritionTask() {
    _nutritionSubscription?.cancel();
    state = state.copyWith(
      nutritionTask: const GenerationTaskState(type: GenerationType.nutrition),
    );
  }

  /// Clear fitness task state
  void clearFitnessTask() {
    _fitnessSubscription?.cancel();
    state = state.copyWith(
      fitnessTask: const GenerationTaskState(type: GenerationType.fitness),
    );
  }
}

/// Provider for generation state
final generationNotifierProvider = StateNotifierProvider<GenerationNotifier, GenerationState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return GenerationNotifier(apiService);
});
