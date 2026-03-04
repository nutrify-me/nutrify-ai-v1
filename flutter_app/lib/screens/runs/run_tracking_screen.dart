import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/run_tracking_provider.dart';
import '../../services/run_tracking_service.dart';

/// Live run tracking screen with real-time map and stats
class RunTrackingScreen extends ConsumerStatefulWidget {
  const RunTrackingScreen({super.key});

  @override
  ConsumerState<RunTrackingScreen> createState() => _RunTrackingScreenState();
}

class _RunTrackingScreenState extends ConsumerState<RunTrackingScreen> {
  final MapController _mapController = MapController();
  bool _hasStartedCountdown = false;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _hasStartedCountdown = true;
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        ref.read(runTrackingProvider.notifier).startRun();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(runTrackingProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Map layer
          _buildMap(state),

          // Stats overlay
          if (state.status == RunTrackingStatus.tracking ||
              state.status == RunTrackingStatus.paused)
            _buildStatsOverlay(state, theme),

          // Countdown overlay
          if (_hasStartedCountdown && _countdown > 0)
            _buildCountdownOverlay(theme),

          // Top bar (back button)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (state.status == RunTrackingStatus.idle)
                    CircleAvatar(
                      backgroundColor: cs.surface,
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: cs.onSurface),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  const Spacer(),
                  if (state.status == RunTrackingStatus.tracking ||
                      state.status == RunTrackingStatus.paused)
                    CircleAvatar(
                      backgroundColor: cs.surface,
                      child: IconButton(
                        icon: Icon(Icons.my_location, color: cs.primary),
                        onPressed: _centerOnCurrentLocation,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(state, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(RunTrackingState state) {
    final routePoints = state.route
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: routePoints.isNotEmpty
            ? routePoints.last
            : const LatLng(28.6139, 77.2090), // Default: Delhi
        initialZoom: 16,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.nutrify.ai',
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 5,
                color: Colors.blue.shade600,
              ),
            ],
          ),
        if (routePoints.isNotEmpty)
          MarkerLayer(
            markers: [
              // Start marker
              Marker(
                point: routePoints.first,
                width: 24,
                height: 24,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                ),
              ),
              // Current position marker
              if (routePoints.length > 1)
                Marker(
                  point: routePoints.last,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withAlpha(100),
                          blurRadius: 12,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatsOverlay(RunTrackingState state, ThemeData theme) {
    final stats = state.stats;
    final isPaused = state.status == RunTrackingStatus.paused;
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: isPaused
                ? Colors.orange.withAlpha(isDark ? 40 : 20)
                : cs.surface.withAlpha(isDark ? 230 : 240),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 60 : 25),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'PAUSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

              // Primary stat: Distance
              Text(
                stats.formattedDistance,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const Text(
                'DISTANCE',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 16),

              // Secondary stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statTile('TIME', stats.formattedDuration, Icons.timer_outlined),
                  Container(width: 1, height: 40, color: theme.dividerColor),
                  _statTile('AVG PACE', '${stats.formattedAvgPace}\n/km',
                      Icons.speed_outlined),
                  Container(width: 1, height: 40, color: theme.dividerColor),
                  _statTile(
                    'PACE',
                    '${stats.formattedCurrentPace}\n/km',
                    Icons.trending_up,
                  ),
                ],
              ),

              if (stats.splits.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                // Latest split
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flag, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Km ${stats.splits.last.km}: ${_formatPace(stats.splits.last.paceSecondsPerKm)}/km',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            height: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownOverlay(ThemeData theme) {
    return Container(
      color: Colors.black.withAlpha(180),
      child: Center(
        child: Text(
          '$_countdown',
          style: const TextStyle(
            fontSize: 120,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(RunTrackingState state, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: (theme.brightness == Brightness.dark ? Colors.black : Colors.black).withAlpha(theme.brightness == Brightness.dark ? 60 : 25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: switch (state.status) {
        RunTrackingStatus.idle => _buildStartButton(),
        RunTrackingStatus.tracking => _buildTrackingControls(),
        RunTrackingStatus.paused => _buildPausedControls(),
        RunTrackingStatus.saving => _buildSavingIndicator(),
        RunTrackingStatus.error => _buildErrorState(state.error),
      },
    );
  }

  Widget _buildStartButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Ready to run?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: _startCountdown,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              elevation: 4,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 32),
                SizedBox(width: 8),
                Text(
                  'START RUN',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Stop & Save (long press for safety)
        SizedBox(
          width: 64,
          height: 64,
          child: ElevatedButton(
            onPressed: () => _stopAndSave(),
            onLongPress: () => _stopAndSave(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
            ),
            child: const Icon(Icons.stop_rounded, size: 28),
          ),
        ),
        // Pause button
        SizedBox(
          width: 80,
          height: 80,
          child: ElevatedButton(
            onPressed: () => ref.read(runTrackingProvider.notifier).pauseRun(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
            ),
            child: const Icon(Icons.pause_rounded, size: 40),
          ),
        ),
        // Center on location
        SizedBox(
          width: 64,
          height: 64,
          child: ElevatedButton(
            onPressed: _centerOnCurrentLocation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
              foregroundColor: Theme.of(context).colorScheme.primary,
              shape: const CircleBorder(),
            ),
            child: const Icon(Icons.my_location, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildPausedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Discard
        SizedBox(
          width: 64,
          height: 64,
          child: ElevatedButton(
            onPressed: () {
              _showDiscardDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade100,
              foregroundColor: Colors.red,
              shape: const CircleBorder(),
            ),
            child: const Icon(Icons.delete_outline, size: 28),
          ),
        ),

        // Resume
        SizedBox(
          width: 80,
          height: 80,
          child: ElevatedButton(
            onPressed: () => ref.read(runTrackingProvider.notifier).resumeRun(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
            ),
            child: const Icon(Icons.play_arrow_rounded, size: 40),
          ),
        ),

        // Stop & Save
        SizedBox(
          width: 64,
          height: 64,
          child: ElevatedButton(
            onPressed: () => _stopAndSave(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
            ),
            child: const Icon(Icons.stop_rounded, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildSavingIndicator() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Saving your run...', style: TextStyle(fontSize: 16)),
      ],
    );
  }

  Widget _buildErrorState(String? error) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: Colors.red.shade400, size: 40),
        const SizedBox(height: 8),
        Text(error ?? 'Something went wrong', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go Back'),
        ),
      ],
    );
  }

  Future<void> _stopAndSave() async {
    final result =
        await ref.read(runTrackingProvider.notifier).stopAndSaveRun();
    if (mounted) {
      if (result != null && result.containsKey('_discarded')) {
        // Run was too short
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['_reason'] ?? 'Run too short'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (result != null) {
        // Run saved successfully
        ref.read(runHistoryProvider.notifier).refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Run saved! ${(result['distance_meters'] as num? ?? 0) / 1000 > 0 ? '${((result['distance_meters'] as num) / 1000).toStringAsFixed(2)} km' : ''}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Error saving
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save run. Check your connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      Navigator.of(context).pop();
    }
  }

  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Run?'),
        content: const Text('This run will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(runTrackingProvider.notifier).discardRun();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  void _centerOnCurrentLocation() {
    final route = ref.read(runTrackingProvider).route;
    if (route.isNotEmpty) {
      _mapController.move(
        LatLng(route.last.latitude, route.last.longitude),
        16,
      );
    }
  }

  String _formatPace(double secondsPerKm) {
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).toInt();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}
