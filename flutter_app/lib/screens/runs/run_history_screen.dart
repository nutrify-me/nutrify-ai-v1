import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/run_tracking_provider.dart';
import 'run_tracking_screen.dart';

/// Displays run history and stats — entry point for the running feature
class RunHistoryScreen extends ConsumerStatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  ConsumerState<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends ConsumerState<RunHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(runHistoryProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(runHistoryProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Running'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(runHistoryProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RunTrackingScreen()),
          );
        },
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.directions_run),
        label: const Text('Start Run'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(runHistoryProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            // Stats summary card
            if (state.stats != null)
              SliverToBoxAdapter(
                child: _buildStatsCard(state.stats!, theme),
              ),

            // Week/month summary
            if (state.stats != null)
              SliverToBoxAdapter(
                child: _buildPeriodCards(state.stats!, theme),
              ),

            // Section header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'Recent Runs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Run list
            if (state.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.runs.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(theme),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildRunTile(state.runs[index], theme),
                  childCount: state.runs.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic> stats, ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bar_chart, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  const Text(
                    'All-Time Stats',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _miniStat(
                    '${stats['total_runs'] ?? 0}',
                    'Runs',
                    Icons.directions_run,
                    Colors.green,
                  ),
                  _miniStat(
                    '${(stats['total_distance_km'] ?? 0).toStringAsFixed(1)}',
                    'km Total',
                    Icons.straighten,
                    Colors.blue,
                  ),
                  _miniStat(
                    _formatPace(
                        (stats['best_pace_seconds_per_km'] as num?)?.toDouble()),
                    'Best Pace',
                    Icons.speed,
                    Colors.orange,
                  ),
                  _miniStat(
                    '${(stats['total_calories'] ?? 0)}',
                    'kcal',
                    Icons.local_fire_department,
                    Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodCards(Map<String, dynamic> stats, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _periodCard(
              'This Week',
              '${stats['runs_this_week'] ?? 0} runs',
              '${(stats['distance_this_week_km'] ?? 0).toStringAsFixed(1)} km',
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _periodCard(
              'This Month',
              '${stats['runs_this_month'] ?? 0} runs',
              '${(stats['distance_this_month_km'] ?? 0).toStringAsFixed(1)} km',
              Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodCard(
      String title, String subtitle, String detail, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withAlpha(50)),
      ),
      color: color.withAlpha(15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
            const SizedBox(height: 4),
            Text(detail,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildRunTile(Map<String, dynamic> run, ThemeData theme) {
    final cs = theme.colorScheme;
    final distance = (run['distance_meters'] as num?) ?? 0;
    final duration = (run['duration_seconds'] as num?) ?? 0;
    final pace = (run['avg_pace_seconds_per_km'] as num?)?.toDouble();
    final calories = run['calories_burned'] as int?;
    final title = run['title'] as String? ?? 'Run';
    final type = run['activity_type'] as String? ?? 'run';
    final startedAt = DateTime.tryParse(run['started_at'] ?? '');

    final km = (distance / 1000).toStringAsFixed(2);
    final durationStr = _formatDuration(duration.toInt());

    IconData typeIcon;
    switch (type) {
      case 'walk':
        typeIcon = Icons.directions_walk;
        break;
      case 'hike':
        typeIcon = Icons.hiking;
        break;
      case 'cycle':
        typeIcon = Icons.directions_bike;
        break;
      default:
        typeIcon = Icons.directions_run;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // TODO: Navigate to run detail screen
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(typeIcon, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (startedAt != null)
                    Text(
                      _formatDate(startedAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _runStatChip(Icons.straighten, '$km km'),
                  _runStatChip(Icons.timer_outlined, durationStr),
                  _runStatChip(Icons.speed, '${_formatPace(pace)}/km'),
                  if (calories != null)
                    _runStatChip(
                        Icons.local_fire_department, '$calories kcal'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runStatChip(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_run, size: 80, color: cs.onSurfaceVariant.withAlpha(80)),
          const SizedBox(height: 16),
          Text(
            'No runs yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Start Run" to track your first run!',
            style: TextStyle(color: cs.onSurfaceVariant.withAlpha(150)),
          ),
        ],
      ),
    );
  }

  String _formatPace(double? secondsPerKm) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--:--';
    final m = secondsPerKm ~/ 60;
    final s = (secondsPerKm % 60).toInt();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
