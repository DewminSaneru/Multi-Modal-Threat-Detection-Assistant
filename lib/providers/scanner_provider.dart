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

final historyProvider = Provider<List<ScanHistoryEntry>>((ref) {
  return ref.watch(mlServiceProvider).history();
});

