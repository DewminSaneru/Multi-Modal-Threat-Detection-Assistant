enum RiskLevel { low, medium, high }

class LinkDetection {
  LinkDetection({
    required this.message,
    required this.isMalicious,
    required this.confidence,
    this.url,
  });

  final String message;
  final bool isMalicious;
  final double confidence;
  final String? url;
}

class EmotionPoint {
  EmotionPoint({required this.label, required this.score, required this.position});

  final String label;
  final double score;
  final int position;
}

class EmotionTimeline {
  EmotionTimeline({required this.points, required this.overall});

  final List<EmotionPoint> points;
  final String overall;
}

class MediaDetection {
  MediaDetection({
    required this.path,
    required this.isUnsafe,
    required this.category,
    required this.confidence,
  });

  final String path;
  final bool isUnsafe;
  final String category;
  final double confidence;
}

class FileDetection {
  FileDetection({
    required this.fileName,
    required this.fileType,
    required this.isMalicious,
    required this.threatProbability,
  });

  final String fileName;
  final String fileType;
  final bool isMalicious;
  final double threatProbability;
}

class ScanHistoryEntry {
  ScanHistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.resultSummary,
    required this.date,
    required this.risk,
  });

  final String id;
  final String type;
  final String title;
  final String resultSummary;
  final DateTime date;
  final RiskLevel risk;
}

