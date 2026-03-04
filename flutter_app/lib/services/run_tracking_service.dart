import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

/// A single tracked GPS point during a run
class TrackPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed; // m/s
  final double? accuracy;
  final DateTime timestamp;
  final double cumulativeDistanceMeters;
  final double cumulativeDurationSeconds;

  TrackPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.accuracy,
    required this.timestamp,
    required this.cumulativeDistanceMeters,
    required this.cumulativeDurationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude_meters': altitude,
        'speed_ms': speed,
        'accuracy_meters': accuracy,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'cumulative_distance_meters': cumulativeDistanceMeters,
        'cumulative_duration_seconds': cumulativeDurationSeconds,
      };
}

/// Per-kilometer split data
class KmSplit {
  final int km;
  final double durationSeconds;
  final double paceSecondsPerKm;
  final double? elevationDelta;

  KmSplit({
    required this.km,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    this.elevationDelta,
  });

  Map<String, dynamic> toJson() => {
        'km': km,
        'duration_seconds': durationSeconds,
        'pace_seconds_per_km': paceSecondsPerKm,
        'elevation_delta': elevationDelta,
      };
}

/// Real-time run statistics
class RunLiveStats {
  final double distanceMeters;
  final int durationSeconds;
  final double? currentPaceSecondsPerKm;
  final double? avgPaceSecondsPerKm;
  final double? currentSpeedKmh;
  final double? elevationGainMeters;
  final int? caloriesBurned;
  final List<KmSplit> splits;

  const RunLiveStats({
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.currentPaceSecondsPerKm,
    this.avgPaceSecondsPerKm,
    this.currentSpeedKmh,
    this.elevationGainMeters,
    this.caloriesBurned,
    this.splits = const [],
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toInt()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedAvgPace {
    if (avgPaceSecondsPerKm == null || avgPaceSecondsPerKm! <= 0) return '--:--';
    final m = avgPaceSecondsPerKm! ~/ 60;
    final s = (avgPaceSecondsPerKm! % 60).toInt();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String get formattedCurrentPace {
    if (currentPaceSecondsPerKm == null || currentPaceSecondsPerKm! <= 0) {
      return '--:--';
    }
    if (currentPaceSecondsPerKm! > 1800) return '--:--'; // > 30 min/km = walking too slow
    final m = currentPaceSecondsPerKm! ~/ 60;
    final s = (currentPaceSecondsPerKm! % 60).toInt();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}

/// GPS-based run tracking service
class RunTrackingService {
  final Logger _logger = Logger();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _durationTimer;

  // State
  bool _isTracking = false;
  bool _isPaused = false;
  DateTime? _startTime;
  DateTime? _pauseTime;
  int _pausedDurationSeconds = 0;

  // GPS data
  final List<TrackPoint> _trackPoints = [];
  final List<KmSplit> _splits = [];
  Position? _lastPosition;
  double _totalDistanceMeters = 0;
  double _elevationGain = 0;
  double _elevationLoss = 0;
  double? _minElevation;
  double? _maxElevation;
  double? _bestPace;
  double _lastSplitDistance = 0;
  DateTime? _lastSplitTime;

  // Stream controllers
  final _statsController = StreamController<RunLiveStats>.broadcast();
  final _locationController = StreamController<TrackPoint>.broadcast();

  // Public streams
  Stream<RunLiveStats> get statsStream => _statsController.stream;
  Stream<TrackPoint> get locationStream => _locationController.stream;

  // Public state
  bool get isTracking => _isTracking;
  bool get isPaused => _isPaused;
  List<TrackPoint> get trackPoints => List.unmodifiable(_trackPoints);
  List<KmSplit> get splits => List.unmodifiable(_splits);

  /// Check & request location permissions
  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _logger.w('Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _logger.w('Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _logger.w('Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Start tracking a run
  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Location permission not granted');

    _isTracking = true;
    _isPaused = false;
    _startTime = DateTime.now();
    _pausedDurationSeconds = 0;
    _totalDistanceMeters = 0;
    _elevationGain = 0;
    _elevationLoss = 0;
    _minElevation = null;
    _maxElevation = null;
    _bestPace = null;
    _lastSplitDistance = 0;
    _lastSplitTime = _startTime;
    _trackPoints.clear();
    _splits.clear();
    _lastPosition = null;

    // Start GPS stream — high accuracy, 3-second intervals
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // minimum 5m between updates
      ),
    ).listen(_onPositionUpdate);

    // Start duration timer (updates every second)
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitStats();
    });

    _logger.i('Run tracking started');
  }

  /// Pause tracking (for water breaks, traffic lights)
  void pauseTracking() {
    if (!_isTracking || _isPaused) return;
    _isPaused = true;
    _pauseTime = DateTime.now();
    _positionSubscription?.pause();
    _logger.i('Run tracking paused');
    _emitStats();
  }

  /// Resume tracking
  void resumeTracking() {
    if (!_isTracking || !_isPaused) return;
    if (_pauseTime != null) {
      _pausedDurationSeconds +=
          DateTime.now().difference(_pauseTime!).inSeconds;
    }
    _isPaused = false;
    _pauseTime = null;
    _positionSubscription?.resume();
    _logger.i('Run tracking resumed');
  }

  /// Stop tracking and return final data
  Future<Map<String, dynamic>> stopTracking() async {
    if (!_isTracking) throw Exception('Not currently tracking');

    _isTracking = false;
    _isPaused = false;
    _positionSubscription?.cancel();
    _durationTimer?.cancel();

    final finishedAt = DateTime.now();
    final totalDuration = _getMovingDurationSeconds();
    final avgPace = _totalDistanceMeters > 0
        ? (totalDuration / (_totalDistanceMeters / 1000))
        : null;
    final avgSpeed = totalDuration > 0
        ? (_totalDistanceMeters / 1000) / (totalDuration / 3600)
        : null;

    // Build the run data payload for the backend
    final runData = {
      'activity_type': 'run',
      'started_at': _startTime!.toUtc().toIso8601String(),
      'finished_at': finishedAt.toUtc().toIso8601String(),
      'duration_seconds': totalDuration,
      'moving_time_seconds': totalDuration,
      'distance_meters': _totalDistanceMeters,
      'avg_pace_seconds_per_km': avgPace,
      'best_pace_seconds_per_km': _bestPace,
      'avg_speed_kmh': avgSpeed,
      'max_speed_kmh': _trackPoints.isNotEmpty
          ? _trackPoints
                  .where((p) => p.speed != null)
                  .fold<double>(0, (max, p) => p.speed! > max ? p.speed! : max) *
              3.6
          : null,
      'elevation_gain_meters': _elevationGain,
      'elevation_loss_meters': _elevationLoss,
      'min_elevation_meters': _minElevation,
      'max_elevation_meters': _maxElevation,
      'splits': _splits.map((s) => s.toJson()).toList(),
      'start_lat': _trackPoints.isNotEmpty ? _trackPoints.first.latitude : null,
      'start_lng': _trackPoints.isNotEmpty ? _trackPoints.first.longitude : null,
      'end_lat': _trackPoints.isNotEmpty ? _trackPoints.last.latitude : null,
      'end_lng': _trackPoints.isNotEmpty ? _trackPoints.last.longitude : null,
      'route_points': _trackPoints.map((p) => p.toJson()).toList(),
    };

    _logger.i(
        'Run completed: ${(_totalDistanceMeters / 1000).toStringAsFixed(2)} km in ${totalDuration}s');

    return runData;
  }

  /// Handle incoming GPS position
  void _onPositionUpdate(Position position) {
    if (_isPaused) return;

    // Filter out low-accuracy readings
    if (position.accuracy > 30) return;

    final now = DateTime.now();
    final movingDuration = _getMovingDurationSeconds().toDouble();

    // Calculate distance from last point
    if (_lastPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Sanity check — ignore jumps >100m/s (GPS glitch)
      double timeDelta = 0;
      if (_trackPoints.isNotEmpty) {
        timeDelta =
            now.difference(_trackPoints.last.timestamp).inMilliseconds / 1000.0;
        if (timeDelta > 0 && distance / timeDelta > 100) {
          _logger.w('GPS glitch detected, ignoring point');
          return;
        }
      }

      _totalDistanceMeters += distance;

      // Elevation tracking
      if (position.altitude != 0) {
        final alt = position.altitude;
        _minElevation = _minElevation == null ? alt : min(_minElevation!, alt);
        _maxElevation = _maxElevation == null ? alt : max(_maxElevation!, alt);

        if (_lastPosition!.altitude != 0) {
          final elevDelta = alt - _lastPosition!.altitude;
          if (elevDelta > 1) {
            _elevationGain += elevDelta;
          } else if (elevDelta < -1) {
            _elevationLoss += elevDelta.abs();
          }
        }
      }

      // Best pace tracking (rolling 100m window)
      if (distance > 0 && timeDelta > 0) {
        final instantPace = (timeDelta / (distance / 1000)); // sec/km
        if (instantPace > 120 && instantPace < 1800) {
          // Between 2:00/km and 30:00/km
          if (_bestPace == null || instantPace < _bestPace!) {
            _bestPace = instantPace;
          }
        }
      }
    }

    // Record track point
    final trackPoint = TrackPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude != 0 ? position.altitude : null,
      speed: position.speed > 0 ? position.speed : null,
      accuracy: position.accuracy,
      timestamp: now,
      cumulativeDistanceMeters: _totalDistanceMeters,
      cumulativeDurationSeconds: movingDuration,
    );

    _trackPoints.add(trackPoint);
    _lastPosition = position;
    _locationController.add(trackPoint);

    // Check for km split
    _checkSplit(now);

    _emitStats();
  }

  /// Check if we've crossed a km boundary
  void _checkSplit(DateTime now) {
    final currentKm = (_totalDistanceMeters / 1000).floor();
    final lastSplitKm = (_lastSplitDistance / 1000).floor();

    if (currentKm > lastSplitKm && currentKm > 0) {
      final splitDuration =
          now.difference(_lastSplitTime ?? _startTime!).inSeconds.toDouble();
      final kmDist = _totalDistanceMeters - _lastSplitDistance;

      _splits.add(KmSplit(
        km: currentKm,
        durationSeconds: splitDuration,
        paceSecondsPerKm: kmDist > 0 ? splitDuration / (kmDist / 1000) : splitDuration,
        elevationDelta: null, // Could calc per-split elevation
      ));

      _lastSplitDistance = _totalDistanceMeters;
      _lastSplitTime = now;

      _logger.i('Split: km $currentKm in ${splitDuration.toInt()}s');
    }
  }

  /// Emit current stats to stream
  void _emitStats() {
    final movingDuration = _getMovingDurationSeconds();
    final avgPace = _totalDistanceMeters > 50 && movingDuration > 0
        ? movingDuration / (_totalDistanceMeters / 1000)
        : null;

    double? currentPace;
    if (_trackPoints.length >= 2) {
      // Average pace over last ~15 seconds of points
      final recentPoints = _trackPoints.reversed.take(5).toList();
      if (recentPoints.length >= 2) {
        final first = recentPoints.last;
        final last = recentPoints.first;
        final dist = last.cumulativeDistanceMeters - first.cumulativeDistanceMeters;
        final dur = last.cumulativeDurationSeconds - first.cumulativeDurationSeconds;
        if (dist > 5 && dur > 0) {
          currentPace = dur / (dist / 1000);
        }
      }
    }

    double? currentSpeed;
    if (_trackPoints.isNotEmpty && _trackPoints.last.speed != null) {
      currentSpeed = _trackPoints.last.speed! * 3.6; // m/s to km/h
    }

    // Rough calorie estimate: ~1 cal/kg/km
    final caloriesBurned = (_totalDistanceMeters / 1000 * 70).toInt(); // assume 70kg

    _statsController.add(RunLiveStats(
      distanceMeters: _totalDistanceMeters,
      durationSeconds: movingDuration,
      currentPaceSecondsPerKm: currentPace,
      avgPaceSecondsPerKm: avgPace,
      currentSpeedKmh: currentSpeed,
      elevationGainMeters: _elevationGain,
      caloriesBurned: caloriesBurned,
      splits: List.unmodifiable(_splits),
    ));
  }

  int _getMovingDurationSeconds() {
    if (_startTime == null) return 0;
    final elapsed = DateTime.now().difference(_startTime!).inSeconds;
    final paused = _isPaused && _pauseTime != null
        ? DateTime.now().difference(_pauseTime!).inSeconds + _pausedDurationSeconds
        : _pausedDurationSeconds;
    return max(0, elapsed - paused);
  }

  /// Release resources
  void dispose() {
    _positionSubscription?.cancel();
    _durationTimer?.cancel();
    _statsController.close();
    _locationController.close();
  }
}
