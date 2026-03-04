import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/progress.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import 'auth_provider.dart';

final _logger = Logger();

// Progress State
class ProgressState {
  final bool isLoading;
  final List<ProgressEntry> entries;
  final String? error;

  const ProgressState({
    this.isLoading = false,
    this.entries = const [],
    this.error,
  });

  ProgressState copyWith({
    bool? isLoading,
    List<ProgressEntry>? entries,
    String? error,
  }) {
    return ProgressState(
      isLoading: isLoading ?? this.isLoading,
      entries: entries ?? this.entries,
      error: error,
    );
  }
}

// Progress Notifier — now with local-first caching
class ProgressNotifier extends StateNotifier<ProgressState> {
  final ApiService _apiService;
  static const _cacheKey = 'progress_entries';

  ProgressNotifier(this._apiService) : super(const ProgressState());

  Future<void> loadProgressEntries() async {
    state = state.copyWith(isLoading: true, error: null);

    // Layer 1: Show cached data immediately
    try {
      final cached = await CacheService.instance.get(_cacheKey);
      if (cached != null) {
        final list = jsonDecode(cached) as List;
        final cachedEntries =
            list.map((e) => ProgressEntry.fromJson(e)).toList();
        state = state.copyWith(isLoading: false, entries: cachedEntries);
        // Background refresh (don't await)
        _refreshFromServer();
        return;
      }
    } catch (e) {
      _logger.w('Cache miss for progress: $e');
    }

    // Layer 2: No cache — fetch from server
    await _refreshFromServer();
  }

  Future<void> _refreshFromServer() async {
    try {
      final entries = await _apiService.getProgressEntries();
      // Update cache
      await CacheService.instance.set(
        _cacheKey,
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
      // Only update state if data actually changed
      if (!_entriesMatch(state.entries, entries)) {
        state = state.copyWith(isLoading: false, entries: entries);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      // If we already have cached data, don't show error
      if (state.entries.isNotEmpty) {
        state = state.copyWith(isLoading: false);
        _logger.w('Background refresh failed (using cache): $e');
      } else {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  bool _entriesMatch(List<ProgressEntry> a, List<ProgressEntry> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> addProgressEntry(ProgressEntryCreate entry) async {
    try {
      // Optimistic: add to state immediately with temp data
      final newEntry = await _apiService.createProgressEntry(entry);
      final updatedEntries = [newEntry, ...state.entries];
      updatedEntries.sort((a, b) => b.entryDate.compareTo(a.entryDate));
      state = state.copyWith(entries: updatedEntries);
      // Update cache
      await _updateCache(updatedEntries);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateProgressEntry(ProgressEntry entry) async {
    try {
      final updatedEntry = await _apiService.updateProgressEntry(entry.id, entry);
      final updatedEntries = state.entries.map((e) {
        return e.id == updatedEntry.id ? updatedEntry : e;
      }).toList();

      state = state.copyWith(entries: updatedEntries);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addWaterIntake(int ml) async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];

      // Find today's entry
      final todayEntry = state.entries.cast<ProgressEntry?>().firstWhere(
        (e) => e?.entryDate == today,
        orElse: () => null,
      );

      if (todayEntry != null) {
        // Update existing entry
        final newIntake = (todayEntry.waterIntakeMl ?? 0) + ml;
        final updatedEntry = ProgressEntry(
          id: todayEntry.id,
          userId: todayEntry.userId,
          entryDate: todayEntry.entryDate,
          weight: todayEntry.weight,
          bodyFatPercentage: todayEntry.bodyFatPercentage,
          muscleMass: todayEntry.muscleMass,
          measurements: todayEntry.measurements,
          moodScore: todayEntry.moodScore,
          energyScore: todayEntry.energyScore,
          stressScore: todayEntry.stressScore,
          sleepHours: todayEntry.sleepHours,
          sleepQuality: todayEntry.sleepQuality,
          waterIntakeMl: newIntake,
          adherenceScore: todayEntry.adherenceScore,
          notes: todayEntry.notes,
          photos: todayEntry.photos,
          createdAt: todayEntry.createdAt,
        );
        await updateProgressEntry(updatedEntry);
      } else {
        // Create new entry with just water intake
        final newEntry = ProgressEntryCreate(
          entryDate: today,
          waterIntakeMl: ml,
        );
        await addProgressEntry(newEntry);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteProgressEntry(String entryId) async {
    try {
      await _apiService.deleteProgressEntry(entryId);
      final updatedEntries = state.entries.where((e) => e.id != entryId).toList();
      state = state.copyWith(entries: updatedEntries);
      await _updateCache(updatedEntries);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _updateCache(List<ProgressEntry> entries) async {
    try {
      await CacheService.instance.set(
        _cacheKey,
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      _logger.w('Failed to update progress cache: $e');
    }
  }
}

// Provider
final progressNotifierProvider = StateNotifierProvider<ProgressNotifier, ProgressState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return ProgressNotifier(apiService);
});