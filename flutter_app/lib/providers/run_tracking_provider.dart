import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../services/run_tracking_service.dart';
import '../services/api_service.dart';

// ─── State ───────────────────────────────────────────────

enum RunTrackingStatus { idle, tracking, paused, saving, error }

class RunTrackingState {
  final RunTrackingStatus status;
  final RunLiveStats stats;
  final List<TrackPoint> route;
  final String? error;

  const RunTrackingState({
    this.status = RunTrackingStatus.idle,
    this.stats = const RunLiveStats(),
    this.route = const [],
    this.error,
  });

  // A default instance to avoid the const issue
  static RunLiveStats get defaultStats => RunLiveStats();

  RunTrackingState copyWith({
    RunTrackingStatus? status,
    RunLiveStats? stats,
    List<TrackPoint>? route,
    String? error,
  }) {
    return RunTrackingState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      route: route ?? this.route,
      error: error,
    );
  }
}

// ─── Run History State ───────────────────────────────────

class RunHistoryState {
  final bool isLoading;
  final List<Map<String, dynamic>> runs;
  final Map<String, dynamic>? stats;
  final String? error;

  const RunHistoryState({
    this.isLoading = false,
    this.runs = const [],
    this.stats,
    this.error,
  });

  RunHistoryState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? runs,
    Map<String, dynamic>? stats,
    String? error,
  }) {
    return RunHistoryState(
      isLoading: isLoading ?? this.isLoading,
      runs: runs ?? this.runs,
      stats: stats ?? this.stats,
      error: error,
    );
  }
}

// ─── Live Tracking Provider ──────────────────────────────

class RunTrackingNotifier extends StateNotifier<RunTrackingState> {
  final RunTrackingService _service = RunTrackingService();
  final ApiService _api = ApiService();
  final Logger _logger = Logger();

  StreamSubscription? _statsSub;
  StreamSubscription? _locationSub;

  RunTrackingNotifier() : super(const RunTrackingState());

  RunTrackingService get service => _service;

  Future<void> startRun() async {
    try {
      await _service.startTracking();

      _statsSub = _service.statsStream.listen((stats) {
        state = state.copyWith(
          status: _service.isPaused
              ? RunTrackingStatus.paused
              : RunTrackingStatus.tracking,
          stats: stats,
        );
      });

      _locationSub = _service.locationStream.listen((point) {
        state = state.copyWith(route: _service.trackPoints);
      });

      state = state.copyWith(status: RunTrackingStatus.tracking);
    } catch (e) {
      state = state.copyWith(
        status: RunTrackingStatus.error,
        error: e.toString(),
      );
    }
  }

  void pauseRun() {
    _service.pauseTracking();
    state = state.copyWith(status: RunTrackingStatus.paused);
  }

  void resumeRun() {
    _service.resumeTracking();
    state = state.copyWith(status: RunTrackingStatus.tracking);
  }

  Future<Map<String, dynamic>?> stopAndSaveRun() async {
    try {
      state = state.copyWith(status: RunTrackingStatus.saving);
      _statsSub?.cancel();
      _locationSub?.cancel();

      final runData = await _service.stopTracking();
      _logger.i('Run data: distance=${runData['distance_meters']}m, duration=${runData['duration_seconds']}s, points=${(runData['route_points'] as List?)?.length ?? 0}');

      // Minimum distance check — don't save micro-runs (10m threshold for testing)
      final distance = (runData['distance_meters'] as num?)?.toDouble() ?? 0;
      if (distance < 10) {
        _logger.w('Run too short ($distance m), discarding');
        state = const RunTrackingState(); // Reset
        return {'_discarded': true, '_reason': 'Run too short (${distance.toInt()}m). Move at least 10 meters.'};
      }

      // Save to backend
      _logger.i('Saving run to backend...');
      final response = await _api.createRunActivity(runData);
      _logger.i('Run saved: ${response['id']}');

      state = const RunTrackingState(); // Reset
      return response;
    } catch (e) {
      _logger.e('Failed to save run: $e');
      state = state.copyWith(
        status: RunTrackingStatus.error,
        error: 'Failed to save run: $e',
      );
      return null;
    }
  }

  void discardRun() {
    _statsSub?.cancel();
    _locationSub?.cancel();
    if (_service.isTracking) {
      _service.stopTracking();
    }
    state = const RunTrackingState();
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _locationSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}

// ─── Run History Provider ────────────────────────────────

class RunHistoryNotifier extends StateNotifier<RunHistoryState> {
  final ApiService _api = ApiService();
  final Logger _logger = Logger();

  RunHistoryNotifier() : super(const RunHistoryState());

  Future<void> loadRuns({int limit = 20, int offset = 0}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final runs = await _api.getRunActivities(limit: limit, offset: offset);
      state = state.copyWith(isLoading: false, runs: runs);
    } catch (e) {
      _logger.e('Failed to load runs: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadStats() async {
    try {
      final stats = await _api.getRunStats();
      state = state.copyWith(stats: stats);
    } catch (e) {
      _logger.e('Failed to load run stats: $e');
    }
  }

  Future<void> refresh() async {
    await Future.wait([loadRuns(), loadStats()]);
  }
}

// ─── Riverpod Providers ──────────────────────────────────

final runTrackingProvider =
    StateNotifierProvider<RunTrackingNotifier, RunTrackingState>(
  (ref) => RunTrackingNotifier(),
);

final runHistoryProvider =
    StateNotifierProvider<RunHistoryNotifier, RunHistoryState>(
  (ref) => RunHistoryNotifier(),
);
