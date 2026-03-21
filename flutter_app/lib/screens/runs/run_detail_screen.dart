import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RunDetailScreen extends StatelessWidget {
  final Map<String, dynamic> run;

  const RunDetailScreen({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final distance = (run['distance_meters'] as num?) ?? 0;
    final duration = (run['duration_seconds'] as num?) ?? 0;
    final avgPace = (run['avg_pace_seconds_per_km'] as num?)?.toDouble();
    final calories = run['calories_burned'] as int?;
    final title = run['title'] as String? ?? 'Run';
    final type = run['activity_type'] as String? ?? 'run';
    final elevationGain = (run['elevation_gain_meters'] as num?)?.toDouble() ?? 0;
    final avgSpeed = (run['avg_speed_kmh'] as num?)?.toDouble();
    final startedAt = DateTime.tryParse(run['started_at'] ?? '');
    final splits = run['splits'] as List? ?? [];
    final routePoints = run['route_points'] as List? ?? [];

    final km = (distance / 1000).toStringAsFixed(2);

    // Build route polyline from GPS points
    final polylinePoints = <LatLng>[];
    for (final point in routePoints) {
      final lat = (point['latitude'] as num?)?.toDouble();
      final lng = (point['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        polylinePoints.add(LatLng(lat, lng));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map
            if (polylinePoints.length >= 2)
              SizedBox(
                height: 250,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: polylinePoints[polylinePoints.length ~/ 2],
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: polylinePoints,
                          color: Colors.blue,
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: polylinePoints.first,
                          width: 24, height: 24,
                          child: const Icon(Icons.circle, color: Colors.green, size: 16),
                        ),
                        Marker(
                          point: polylinePoints.last,
                          width: 24, height: 24,
                          child: const Icon(Icons.flag, color: Colors.red, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Container(
                height: 150,
                color: Colors.grey.shade200,
                child: const Center(child: Text('No route data available')),
              ),

            // Date & Type
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_typeIcon(type), color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    type[0].toUpperCase() + type.substring(1),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (startedAt != null)
                    Text(
                      _formatFullDate(startedAt),
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Stats grid
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _statTile(context, 'Distance', '$km km', Icons.straighten, Colors.blue),
                      _statTile(context, 'Duration', _formatDuration(duration.toInt()), Icons.timer, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statTile(context, 'Avg Pace', '${_formatPace(avgPace)}/km', Icons.speed, Colors.orange),
                      _statTile(context, 'Calories', '${calories ?? '--'} kcal', Icons.local_fire_department, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _statTile(context, 'Elevation', '${elevationGain.toStringAsFixed(0)} m', Icons.terrain, Colors.brown),
                      _statTile(context, 'Avg Speed', avgSpeed != null ? '${avgSpeed.toStringAsFixed(1)} km/h' : '--', Icons.speed, Colors.purple),
                    ],
                  ),
                ],
              ),
            ),

            // Splits
            if (splits.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Splits', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              ...splits.asMap().entries.map((entry) {
                final i = entry.key;
                final split = entry.value;
                final splitPace = (split['pace_seconds_per_km'] as num?)?.toDouble();
                final splitElev = (split['elevation_delta'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                  ),
                  title: Text('Km ${i + 1}'),
                  subtitle: Text('Pace: ${_formatPace(splitPace)}'),
                  trailing: splitElev != 0
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(splitElev > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: splitElev > 0 ? Colors.red : Colors.green),
                            Text('${splitElev.abs().toStringAsFixed(0)}m', style: const TextStyle(fontSize: 13)),
                          ],
                        )
                      : null,
                );
              }),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'walk': return Icons.directions_walk;
      case 'hike': return Icons.hiking;
      case 'cycle': return Icons.directions_bike;
      default: return Icons.directions_run;
    }
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
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
