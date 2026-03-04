import 'dart:convert';
import 'package:logger/logger.dart';
import 'cache_service.dart';
import 'api_service.dart';
import '../models/progress.dart';

final _logger = Logger();

/// Queued mutation — stored in SQLite until synced to server
class QueuedMutation {
  final String id;
  final String type; // 'meal_log', 'progress_entry', 'water_intake', 'run_activity'
  final String method; // 'create', 'update', 'delete'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  QueuedMutation({
    required this.id,
    required this.type,
    required this.method,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'method': method,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
      };

  factory QueuedMutation.fromJson(Map<String, dynamic> json) => QueuedMutation(
        id: json['id'],
        type: json['type'],
        method: json['method'],
        payload: json['payload'] is String
            ? jsonDecode(json['payload'])
            : json['payload'],
        createdAt: DateTime.parse(json['created_at']),
        retryCount: json['retry_count'] ?? 0,
      );
}

/// Offline-first mutation queue backed by SQLite.
/// Enqueues mutations locally and processes them when online.
class OfflineMutationQueue {
  static final OfflineMutationQueue instance = OfflineMutationQueue._();
  OfflineMutationQueue._();

  static const _queueCacheKey = 'offline_mutation_queue';
  final ApiService _api = ApiService();
  bool _isProcessing = false;

  /// Enqueue a mutation. Returns immediately.
  Future<void> enqueue(QueuedMutation mutation) async {
    final queue = await _loadQueue();
    queue.add(mutation);
    await _saveQueue(queue);
    _logger.i('Enqueued ${mutation.type}:${mutation.method} (${mutation.id})');

    // Try to process immediately (non-blocking)
    processQueue();
  }

  /// Process all pending mutations in FIFO order.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queue = await _loadQueue();
      if (queue.isEmpty) return;

      _logger.i('Processing ${queue.length} queued mutations');
      final processed = <String>[];

      for (final mutation in queue) {
        try {
          await _executeMutation(mutation);
          processed.add(mutation.id);
          _logger.d('Synced ${mutation.type}:${mutation.method}');
        } catch (e) {
          mutation.retryCount++;
          if (mutation.retryCount >= 5) {
            _logger.e('Mutation ${mutation.id} failed 5 times, discarding');
            processed.add(mutation.id);
          } else {
            _logger.w(
                'Mutation ${mutation.id} failed (attempt ${mutation.retryCount}): $e');
            break; // Stop processing — likely offline
          }
        }
      }

      // Remove processed items
      if (processed.isNotEmpty) {
        queue.removeWhere((m) => processed.contains(m.id));
        await _saveQueue(queue);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _executeMutation(QueuedMutation mutation) async {
    switch (mutation.type) {
      case 'meal_log':
        if (mutation.method == 'create') {
          final p = mutation.payload;
          await _api.logMeal(
            mealDate: p['meal_date'] ?? '',
            mealType: p['meal_type'] ?? 'snack',
            customMealName: p['custom_meal_name'],
            calories: p['calories'],
            proteinGrams: p['protein_grams']?.toDouble(),
            carbsGrams: p['carbs_grams']?.toDouble(),
            fatGrams: p['fat_grams']?.toDouble(),
          );
        }
        break;

      case 'progress_entry':
        if (mutation.method == 'create') {
          await _api.createProgressEntry(
            ProgressEntryCreate.fromJson(mutation.payload),
          );
        }
        break;

      case 'run_activity':
        if (mutation.method == 'create') {
          await _api.createRunActivity(mutation.payload);
        }
        break;

      default:
        _logger.w('Unknown mutation type: ${mutation.type}');
    }
  }

  /// Get count of pending mutations
  Future<int> pendingCount() async {
    final queue = await _loadQueue();
    return queue.length;
  }

  Future<List<QueuedMutation>> _loadQueue() async {
    try {
      final raw = await CacheService.instance.get(_queueCacheKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => QueuedMutation.fromJson(e)).toList();
      }
    } catch (e) {
      _logger.w('Failed to load mutation queue: $e');
    }
    return [];
  }

  Future<void> _saveQueue(List<QueuedMutation> queue) async {
    await CacheService.instance.set(
      _queueCacheKey,
      jsonEncode(queue.map((m) => m.toJson()).toList()),
    );
  }
}
