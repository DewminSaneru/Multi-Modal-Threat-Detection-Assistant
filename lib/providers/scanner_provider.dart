import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/detection_models.dart';
import '../services/mock_ml_service.dart';

final mlServiceProvider = Provider<MockMlService>((ref) => MockMlService());

final linkDetectionsProvider =
    StateProvider.autoDispose<List<LinkDetection>>((ref) => const []);

final emotionTimelineProvider =
    StateProvider.autoDispose<EmotionTimeline?>((ref) => null);

final mediaDetectionProvider =
    StateProvider.autoDispose<MediaDetection?>((ref) => null);

final fileDetectionProvider =
    StateProvider.autoDispose<FileDetection?>((ref) => null);

/// Mutable list of scan history entries; scanners add to this on each completed scan.
class ScanHistoryNotifier extends StateNotifier<List<ScanHistoryEntry>> {
  ScanHistoryNotifier() : super([]);

  void addEntry(ScanHistoryEntry entry) {
    state = [entry, ...state];
  }
}

final scanHistoryNotifierProvider =
    StateNotifierProvider<ScanHistoryNotifier, List<ScanHistoryEntry>>((ref) {
  return ScanHistoryNotifier();
});

/// Real scan history (newest first). Use this in the history screen.
final historyProvider = Provider<List<ScanHistoryEntry>>((ref) {
  return ref.watch(scanHistoryNotifierProvider);
});

