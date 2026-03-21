import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/workout_cache_service.dart';

class ExerciseProgressScreen extends ConsumerStatefulWidget {
  const ExerciseProgressScreen({super.key});

  @override
  ConsumerState<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends ConsumerState<ExerciseProgressScreen> {
  List<String> _exerciseNames = [];
  String? _selectedExercise;
  List<ExerciseSetLocal> _sets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => _isLoading = true);
    try {
      final cache = WorkoutCacheService.instance;
      final recent = await cache.getRecentWorkouts(days: 365);
      final names = <String>{};
      for (final workout in recent) {
        final sets = await cache.getSessionSets(workout.id);
        for (final s in sets) {
          if (!s.isWarmup) names.add(s.exerciseName);
        }
      }
      final sorted = names.toList()..sort();
      setState(() {
        _exerciseNames = sorted;
        _isLoading = false;
        if (sorted.isNotEmpty && _selectedExercise == null) {
          _selectedExercise = sorted.first;
          _loadSets(sorted.first);
        }
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSets(String exerciseName) async {
    final sets = await WorkoutCacheService.instance.getExerciseHistory(exerciseName, limit: 200);
    setState(() => _sets = sets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Progress')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exerciseNames.isEmpty
              ? const Center(child: Text('Complete some workouts to see progress'))
              : Column(
                  children: [
                    // Exercise selector
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        value: _selectedExercise,
                        decoration: const InputDecoration(
                          labelText: 'Exercise',
                          border: OutlineInputBorder(),
                        ),
                        items: _exerciseNames
                            .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedExercise = v);
                            _loadSets(v);
                          }
                        },
                      ),
                    ),

                    // Chart
                    if (_sets.length >= 2)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 250,
                          child: _buildChart(),
                        ),
                      ),

                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Estimated 1RM over time',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ),

                    const Divider(height: 32),

                    // Recent sets list
                    Expanded(
                      child: _sets.isEmpty
                          ? const Center(child: Text('No data for this exercise'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _sets.length,
                              itemBuilder: (ctx, i) {
                                final s = _sets[i];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: s.isPR ? Colors.amber.shade100 : Colors.grey.shade200,
                                    child: s.isPR
                                        ? const Icon(Icons.emoji_events, size: 14, color: Colors.amber)
                                        : Text('${s.setNumber}', style: const TextStyle(fontSize: 12)),
                                  ),
                                  title: Text('${s.weightKg} kg × ${s.reps} reps'),
                                  subtitle: Text(_formatDate(s.completedAt)),
                                  trailing: Text(
                                    'e1RM: ${_estimated1RM(s.weightKg, s.reps).toStringAsFixed(1)} kg',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildChart() {
    // Group sets by date - take max e1RM per day
    final dataByDate = <DateTime, double>{};
    for (final s in _sets.reversed) {
      final date = DateTime(s.completedAt.year, s.completedAt.month, s.completedAt.day);
      final e1rm = _estimated1RM(s.weightKg, s.reps);
      if (!dataByDate.containsKey(date) || e1rm > dataByDate[date]!) {
        dataByDate[date] = e1rm;
      }
    }

    if (dataByDate.length < 2) return const Center(child: Text('Need more data'));

    final sortedDates = dataByDate.keys.toList()..sort();
    final firstDate = sortedDates.first;
    final spots = sortedDates.map((d) {
      return FlSpot(
        d.difference(firstDate).inDays.toDouble(),
        dataByDate[d]!,
      );
    }).toList();

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 3,
            dotData: FlDotData(show: spots.length < 20),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 11)),
            ),
          ),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  double _estimated1RM(double weight, int reps) {
    if (reps <= 0 || weight <= 0) return 0;
    if (reps == 1) return weight;
    // Epley formula
    return weight * (1 + reps / 30);
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
