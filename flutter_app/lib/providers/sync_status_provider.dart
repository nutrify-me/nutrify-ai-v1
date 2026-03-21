import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_mutation_queue.dart';
import '../services/workout_cache_service.dart';

/// Tracks pending sync count and connectivity status
class SyncStatusState {
  final int pendingCount;
  final bool isOnline;

  const SyncStatusState({this.pendingCount = 0, this.isOnline = true});

  SyncStatusState copyWith({int? pendingCount, bool? isOnline}) {
    return SyncStatusState(
      pendingCount: pendingCount ?? this.pendingCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class SyncStatusNotifier extends StateNotifier<SyncStatusState> {
  Timer? _pollTimer;

  SyncStatusNotifier() : super(const SyncStatusState()) {
    _startPolling();
  }

  void _startPolling() {
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final mutationCount = await OfflineMutationQueue.instance.pendingCount();
      final workoutQueue = await WorkoutCacheService.instance.getPendingSyncQueue();
      final total = mutationCount + workoutQueue.length;
      state = state.copyWith(pendingCount: total);
    } catch (_) {}
  }

  void setOnline(bool online) {
    state = state.copyWith(isOnline: online);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final syncStatusProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncStatusState>(
  (ref) => SyncStatusNotifier(),
);

/// A small banner widget that shows pending sync items
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);

    if (syncStatus.pendingCount <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.orange.shade700,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.sync, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${syncStatus.pendingCount} item${syncStatus.pendingCount == 1 ? '' : 's'} pending sync',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
