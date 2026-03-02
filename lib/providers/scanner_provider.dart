// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../models/detection_models.dart';
// import '../services/mock_ml_service.dart';

// final mlServiceProvider = Provider<MockMlService>((ref) => MockMlService());

// final linkDetectionsProvider =
//     StateProvider.autoDispose<List<LinkDetection>>((ref) => const []);

// final emotionTimelineProvider =
//     StateProvider.autoDispose<EmotionTimeline?>((ref) => null);

// final mediaDetectionProvider =
//     StateProvider.autoDispose<MediaDetection?>((ref) => null);

// final fileDetectionProvider =
//     StateProvider.autoDispose<FileDetection?>((ref) => null);

// /// Mutable list of scan history entries; scanners add to this on each completed scan.
// class ScanHistoryNotifier extends StateNotifier<List<ScanHistoryEntry>> {
//   ScanHistoryNotifier() : super([]);

//   void addEntry(ScanHistoryEntry entry) {
//     state = [entry, ...state];
//   }
// }

// final scanHistoryNotifierProvider =
//     StateNotifierProvider<ScanHistoryNotifier, List<ScanHistoryEntry>>((ref) {
//   return ScanHistoryNotifier();
// });

// /// Real scan history (newest first). Use this in the history screen.
// final historyProvider = Provider<List<ScanHistoryEntry>>((ref) {
//   return ref.watch(scanHistoryNotifierProvider);
// });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/detection_models.dart';
import '../services/api_service.dart';
import '../services/mock_ml_service.dart';
import 'auth_provider.dart';

final mlServiceProvider = Provider<MockMlService>((ref) => MockMlService());

final linkDetectionsProvider =
    StateProvider.autoDispose<List<LinkDetection>>((ref) => const []);

final emotionTimelineProvider =
    StateProvider.autoDispose<EmotionTimeline?>((ref) => null);

final mediaDetectionProvider =
    StateProvider.autoDispose<MediaDetection?>((ref) => null);

final fileDetectionProvider =
    StateProvider.autoDispose<FileDetection?>((ref) => null);

// ── Scan History Notifier ─────────────────────────────────────────────────────
// Holds the in-memory list AND handles saving/loading from MongoDB.

class ScanHistoryNotifier extends StateNotifier<List<ScanHistoryEntry>> {
  ScanHistoryNotifier(this._ref) : super([]);

  final Ref _ref;
  final _api = ApiService();

  // Called once after login to populate history from MongoDB
  Future<void> loadFromServer() async {
    final token = _ref.read(authProvider).token;
    if (token == null) return;

    try {
      final raw = await _api.getHistory(token);
      final entries = raw.map((item) {
        final map = item as Map<String, dynamic>;
        return ScanHistoryEntry(
          id:            map['_id'] as String? ?? '',
          type:          map['type'] as String? ?? '',
          title:         map['title'] as String? ?? '',
          resultSummary: map['resultSummary'] as String? ?? '',
          date:          DateTime.tryParse(map['scannedAt'] as String? ?? '') ??
                         DateTime.now(),
          risk:          _parseRisk(map['risk'] as String? ?? 'low'),
        );
      }).toList();

      // Already sorted newest-first by the API
      state = entries;
    } catch (_) {
      // If loading fails, just keep empty — don't crash the app
    }
  }

  // Called by each scanner after a completed scan
  Future<void> addEntry(ScanHistoryEntry entry) async {
    // 1. Update UI immediately (optimistic)
    state = [entry, ...state];

    // 2. Save to MongoDB in the background
    final token = _ref.read(authProvider).token;
    if (token == null) return;

    try {
      await _api.saveScanHistory(
        token:         token,
        type:          entry.type,
        title:         entry.title,
        resultSummary: entry.resultSummary,
        risk:          entry.risk.name,          // 'low' | 'medium' | 'high'
        details:       {},
      );
    } catch (_) {
      // Save failed silently — entry still shows in local state for this session
    }
  }

  // Delete a single entry (from UI and MongoDB)
  Future<void> removeEntry(String id) async {
    state = state.where((e) => e.id != id).toList();

    final token = _ref.read(authProvider).token;
    if (token == null) return;

    try {
      await _api.deleteHistory(token, id);
    } catch (_) {}
  }

  void clearAll() => state = [];

  RiskLevel _parseRisk(String value) {
    switch (value) {
      case 'high':   return RiskLevel.high;
      case 'medium': return RiskLevel.medium;
      default:       return RiskLevel.low;
    }
  }
}

final scanHistoryNotifierProvider =
    StateNotifierProvider<ScanHistoryNotifier, List<ScanHistoryEntry>>((ref) {
  return ScanHistoryNotifier(ref);
});

/// Read-only view used by the history screen.
final historyProvider = Provider<List<ScanHistoryEntry>>((ref) {
  return ref.watch(scanHistoryNotifierProvider);
});