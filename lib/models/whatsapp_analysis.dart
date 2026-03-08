/// whatsapp_analysis.dart
///
/// Data models for the WhatsApp Emotion Risk Monitor backend responses.
/// Mirrors the payload shapes emitted by the deployed Node.js server at
/// http://144.126.223.193:3000 — do NOT change field names here without
/// changing the backend first.

class AnalysisResult {
  final String text;
  final String emotion;
  final String intensity;
  final double confidence;
  final double messageRisk;
  final String direction;
  final Map<String, double> emotionScores;
  final Map<String, double> intensityScores;

  const AnalysisResult({
    required this.text,
    required this.emotion,
    required this.intensity,
    required this.confidence,
    required this.messageRisk,
    required this.direction,
    this.emotionScores = const {},
    this.intensityScores = const {},
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> j) => AnalysisResult(
        text: j['text'] as String? ?? '',
        emotion: j['emotion'] as String? ?? 'neutral',
        intensity: j['intensity'] as String? ?? 'mild',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        messageRisk: (j['message_risk'] as num?)?.toDouble() ?? 0.0,
        direction: j['direction'] as String? ?? 'received',
        emotionScores: _scores(j['emotion_scores']),
        intensityScores: _scores(j['intensity_scores']),
      );

  static Map<String, double> _scores(dynamic raw) {
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        e.key as String: (e.value as num).toDouble()
    };
  }
}

class WindowData {
  final String chatId;
  final List<AnalysisResult> window;
  final double windowRisk;
  final String dominantEmotion;

  const WindowData({
    required this.chatId,
    required this.window,
    required this.windowRisk,
    required this.dominantEmotion,
  });

  factory WindowData.fromJson(Map<String, dynamic> j) {
    final raw = j['window'];
    final win = raw is List
        ? raw
            .map((e) => AnalysisResult.fromJson(e as Map<String, dynamic>))
            .toList()
        : <AnalysisResult>[];
    return WindowData(
      chatId: j['chatId'] as String? ?? '',
      window: win,
      windowRisk: (j['windowRisk'] as num?)?.toDouble() ?? 0.0,
      dominantEmotion: j['dominantEmotion'] as String? ?? 'neutral',
    );
  }
}

class ChatItem {
  final String id;
  final String name;
  final int unreadCount;

  const ChatItem({required this.id, required this.name, this.unreadCount = 0});

  factory ChatItem.fromJson(Map<String, dynamic> j) => ChatItem(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? j['id'] as String? ?? '',
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) => other is ChatItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ─── Alert model ──────────────────────────────────────────────────────────────

/// Severity tier for a fired risk alert.
/// Thresholds: MILD ≥ 40, MEDIUM ≥ 55, HIGH ≥ 70  (window risk score).
enum AlertLevel { mild, medium, high }

extension AlertLevelExt on AlertLevel {
  String get label {
    switch (this) {
      case AlertLevel.mild:   return 'MILD';
      case AlertLevel.medium: return 'MEDIUM';
      case AlertLevel.high:   return 'HIGH';
    }
  }
}

/// Fired when window risk crosses [kAlertThreshold].
/// Intentionally contains NO message content — only aggregate risk metadata.
class RiskAlert {
  final AlertLevel level;
  final double windowRisk;
  final String dominantEmotion;
  final int messageCount;
  final DateTime timestamp;

  const RiskAlert({
    required this.level,
    required this.windowRisk,
    required this.dominantEmotion,
    required this.messageCount,
    required this.timestamp,
  });
}
