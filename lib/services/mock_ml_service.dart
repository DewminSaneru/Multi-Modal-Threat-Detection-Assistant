import 'dart:math';

import '../models/detection_models.dart';

class MockMlService {
  final _rng = Random();

  List<LinkDetection> detectLinks(String chat) {
    final lines = chat.split('\n');
    return lines
        .asMap()
        .entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map((entry) {
      final containsUrl = entry.value.contains('http');
      final malicious = containsUrl && _rng.nextBool();
      return LinkDetection(
        message: entry.value,
        isMalicious: malicious,
        confidence: _rng.nextDouble(),
        url: containsUrl ? 'https://example.com' : null,
      );
    }).toList();
  }

  EmotionTimeline detectEmotion(String chat) {
    final points = List.generate(
      8,
      (i) => EmotionPoint(
        label: ['calm', 'joy', 'anger', 'fear'][i % 4],
        score: 0.4 + _rng.nextDouble() * 0.6,
        position: i,
      ),
    );
    return EmotionTimeline(points: points, overall: 'mixed');
  }

  MediaDetection scanMedia(String path) {
    final unsafe = _rng.nextBool();
    final categories = ['nudity', 'violence', 'hate symbols', 'safe'];
    final category = unsafe ? categories[_rng.nextInt(3)] : 'safe';
    return MediaDetection(
      path: path,
      isUnsafe: unsafe,
      category: category,
      confidence: 0.5 + _rng.nextDouble() * 0.5,
    );
  }

  FileDetection scanFile(String name, String type) {
    final malicious = _rng.nextBool();
    return FileDetection(
      fileName: name,
      fileType: type,
      isMalicious: malicious,
      threatProbability: 0.4 + _rng.nextDouble() * 0.6,
    );
  }

  List<ScanHistoryEntry> history() {
    return List.generate(
      12,
      (i) => ScanHistoryEntry(
        id: 'scan-$i',
        type: ['chat', 'media', 'file'][i % 3],
        title: 'Scan #$i',
        resultSummary: i.isEven ? 'No threat found' : 'Potential risk detected',
        date: DateTime.now().subtract(Duration(days: i)),
        risk: RiskLevel.values[i % RiskLevel.values.length],
      ),
    );
  }
}

