import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../services/workout_cache_service.dart';
import 'active_workout_screen.dart';
import '../../models/fitness.dart';

class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  List<WorkoutSessionLocal> _sessions = [];
  Map<String, List<ExerciseSetLocal>> _sessionSets = {};
  bool _isLoading = true;
  String? _expandedSessionId;
  int _daysToLoad = 30;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await WorkoutCacheService.instance.getRecentWorkouts(days: _daysToLoad);
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSetsForSession(String sessionId) async {
    if (_sessionSets.containsKey(sessionId)) return;
    final sets = await WorkoutCacheService.instance.getSessionSets(sessionId);
    setState(() {
      _sessionSets[sessionId] = sets;
    });
  }

  /// Group sessions by date
  Map<String, List<WorkoutSessionLocal>> _groupByDate() {
    final Map<String, List<WorkoutSessionLocal>> grouped = {};
    for (final session in _sessions) {
      final date = session.completedAt ?? session.startedAt;
      final key = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(key, () => []).add(session);
    }
    return grouped;
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    if (now.difference(date).inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Workout History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: Icon(Icons.filter_list, color: theme.colorScheme.onSurface),
            onSelected: (days) {
              _daysToLoad = days;
              _loadHistory();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 7, child: Text('Last 7 days')),
              const PopupMenuItem(value: 30, child: Text('Last 30 days')),
              const PopupMenuItem(value: 90, child: Text('Last 90 days')),
              const PopupMenuItem(value: 365, child: Text('All time')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: _buildHistoryList(theme, isDark),
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Workouts Yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a workout and it will show up here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(ThemeData theme, bool isDark) {
    final grouped = _groupByDate();
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    // Compute summary stats
    final totalSessions = _sessions.length;
    final totalVolume = _sessions.fold<int>(0, (sum, s) => sum + s.totalVolume);
    final totalMinutes = _sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: dateKeys.length + 1, // +1 for summary header
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSummaryHeader(theme, isDark, totalSessions, totalVolume, totalMinutes);
        }
        final dateKey = dateKeys[index - 1];
        final sessions = grouped[dateKey]!;
        return _buildDateSection(theme, isDark, dateKey, sessions);
      },
    );
  }

  Widget _buildSummaryHeader(ThemeData theme, bool isDark, int sessions, int volume, int minutes) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A5F), const Color(0xFF2563EB)]
              : [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last $_daysToLoad days',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryStatItem('Workouts', '$sessions', Icons.fitness_center),
              const SizedBox(width: 24),
              _buildSummaryStatItem('Volume', '${(volume / 1000).toStringAsFixed(1)}t', Icons.monitor_weight_outlined),
              const SizedBox(width: 24),
              _buildSummaryStatItem('Time', '${minutes}m', Icons.schedule),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDateSection(ThemeData theme, bool isDark, String dateKey, List<WorkoutSessionLocal> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                _formatDateHeader(dateKey),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${sessions.length} workout${sessions.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...sessions.map((session) => _buildSessionCard(theme, isDark, session)),
      ],
    );
  }

  Widget _buildSessionCard(ThemeData theme, bool isDark, WorkoutSessionLocal session) {
    final isExpanded = _expandedSessionId == session.id;
    final sets = _sessionSets[session.id] ?? [];
    final completedAt = session.completedAt ?? session.startedAt;
    final timeStr = DateFormat('h:mm a').format(completedAt);
    final durationMin = session.durationSeconds ~/ 60;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          // Tap header to expand
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedSessionId = null;
                } else {
                  _expandedSessionId = session.id;
                  _loadSetsForSession(session.id);
                }
              });
            },
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Colored icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fitness_center,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name + stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.workoutName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildChip(theme, isDark, Icons.schedule, '${durationMin}m'),
                            const SizedBox(width: 8),
                            _buildChip(theme, isDark, Icons.monitor_weight_outlined, '${session.totalVolume} kg'),
                            const SizedBox(width: 8),
                            _buildChip(theme, isDark, Icons.access_time_filled, timeStr),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Sync status dot
                  if (session.syncStatus == 'synced')
                    Icon(Icons.cloud_done, size: 16, color: Colors.green.withOpacity(0.7))
                  else
                    Icon(Icons.cloud_off, size: 16, color: Colors.orange.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
            ),
            if (sets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              _buildExpandedSets(theme, isDark, sets),
            // Edit button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _editWorkout(session),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit Workout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(ThemeData theme, bool isDark, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedSets(ThemeData theme, bool isDark, List<ExerciseSetLocal> sets) {
    // Group sets by exercise name
    final Map<String, List<ExerciseSetLocal>> exerciseGroups = {};
    for (final set in sets) {
      exerciseGroups.putIfAbsent(set.exerciseName, () => []).add(set);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: exerciseGroups.entries.map((entry) {
          final exerciseName = entry.key;
          final exerciseSets = entry.value;
          final totalSets = exerciseSets.where((s) => !s.isWarmup).length;

          // Best set (highest volume = weight * reps)
          ExerciseSetLocal? bestSet;
          for (final s in exerciseSets.where((s) => !s.isWarmup)) {
            if (bestSet == null || (s.weightKg * s.reps) > (bestSet.weightKg * bestSet.reps)) {
              bestSet = s;
            }
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.4 : 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Exercise name row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exerciseName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalSets sets',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Set details
                ...exerciseSets.map((s) {
                  final isBest = s == bestSet;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        // Set number badge
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: s.isWarmup
                                ? Colors.orange.withOpacity(0.2)
                                : (isBest ? Colors.amber.withOpacity(0.2) : Colors.green.withOpacity(0.15)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              s.isWarmup ? 'W' : '${s.setNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: s.isWarmup ? Colors.orange : (isBest ? Colors.amber.shade700 : Colors.green),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Weight x reps
                        if (s.weightKg > 0)
                          Text(
                            '${s.weightKg.toStringAsFixed(1)} kg × ${s.reps}',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                              fontWeight: isBest ? FontWeight.w600 : FontWeight.w400,
                            ),
                          )
                        else
                          Text(
                            '${s.reps} reps',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        if (s.isPR) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star, size: 14, color: Colors.amber.shade600),
                          const SizedBox(width: 2),
                          Text(
                            'PR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade600,
                            ),
                          ),
                        ],
                        if (isBest && !s.isPR && !s.isWarmup) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Best set',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _editWorkout(WorkoutSessionLocal session) {
    // Create a minimal Workout object for the active workout screen
    final workout = Workout(
      id: session.workoutId ?? session.id,
      name: session.workoutName,
      durationMinutes: session.durationSeconds ~/ 60,
      exercises: [],
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          workout: workout,
          editMode: true,
          existingSession: session,
        ),
      ),
    ).then((_) => _loadHistory()); // Refresh after editing
  }
}
