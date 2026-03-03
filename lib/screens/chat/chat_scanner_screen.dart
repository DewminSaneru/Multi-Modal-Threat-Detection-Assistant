import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

class ChatScannerScreen extends ConsumerStatefulWidget {
  const ChatScannerScreen({super.key});

  @override
  ConsumerState<ChatScannerScreen> createState() => _ChatScannerScreenState();
}

class _ChatScannerScreenState extends ConsumerState<ChatScannerScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _errorMessage;
  String? _statusMessage;

  // ── API results ─────────────────────────────────────────────────────────────
  Map<String, double>? _emotions;
  SpamResult? _spamResult;

  // ── API credentials ──────────────────────────────────────────────────────────
  static const String _emotionApiUrl =
      'https://api.apilayer.com/text_to_emotion';
  static const String _emotionApiKey = 'Bj6vvmjOvF06QJ0uYAW3YfHoZp1LnZ7g';

  static const String _spamApiUrl =
      'https://oopspam.p.rapidapi.com/v1/spamdetection';
  static const String _spamApiKey =
      'c0ab15b0d3msh6aec695031d9dc3p182f36jsne90166228baf';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Run both APIs in parallel ─────────────────────────────────────────────

  Future<void> _runScan() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some text to scan.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _emotions = null;
      _spamResult = null;
      _statusMessage = 'Analyzing emotions and spam...';
    });

    try {
      // Run both APIs simultaneously
      final results = await Future.wait([
        _fetchEmotions(text),
        _fetchSpam(text),
      ]);

      final emotions = results[0] as Map<String, double>;
      final spam     = results[1] as SpamResult;

      setState(() {
        _emotions     = emotions;
        _spamResult   = spam;
        _loading      = false;
        _statusMessage = null;
      });

      _addToHistory(emotions, spam);
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Emotion API ───────────────────────────────────────────────────────────

  Future<Map<String, double>> _fetchEmotions(String text) async {
    final response = await http
        .post(
          Uri.parse(_emotionApiUrl),
          headers: {
            'apikey':       _emotionApiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'body': text}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
          'Emotion API failed (status ${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  // ── Spam API ──────────────────────────────────────────────────────────────

  Future<SpamResult> _fetchSpam(String text) async {
    final response = await http
        .post(
          Uri.parse(_spamApiUrl),
          headers: {
            'X-RapidAPI-Key':  _spamApiKey,
            'X-RapidAPI-Host': 'oopspam.p.rapidapi.com',
            'Content-Type':    'application/json',
          },
          body: jsonEncode({
            'content':        text,
            'checkForLength': true,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Spam API failed (status ${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final score   = (decoded['Score'] as num?)?.toInt() ?? 0;
    final details = decoded['Details'] as Map<String, dynamic>? ?? {};

    return SpamResult(
      score:           score,
      isContentSpam:   details['isContentSpam'] as String? ?? 'nospam',
      numberOfSpamWords: (details['numberOfSpamWords'] as num?)?.toInt() ?? 0,
      spamWords:       (details['spamWords'] as List<dynamic>?)
                           ?.map((e) => e.toString())
                           .toList() ??
                       [],
    );
  }

  // ── Compute overall risk ──────────────────────────────────────────────────

  RiskLevel _computeRisk(
      Map<String, double> emotions, SpamResult spam) {
    // High risk: spam score >= 3 OR spam content detected
    if (spam.score >= 3 || spam.isContentSpam == 'spam') {
      return RiskLevel.high;
    }
    // Medium risk: spam score == 2 OR high negative emotions
    final anger   = emotions['Angry']   ?? emotions['Anger']   ?? 0.0;
    final fear    = emotions['Fear']    ?? 0.0;
    final sad     = emotions['Sad']     ?? emotions['Sadness'] ?? 0.0;
    final negScore = anger + fear + sad;

    if (spam.score == 2 || negScore >= 1.2) {
      return RiskLevel.medium;
    }
    return RiskLevel.low;
  }

  // ── Add to history ────────────────────────────────────────────────────────

  void _addToHistory(Map<String, double> emotions, SpamResult spam) {
    final risk = _computeRisk(emotions, spam);

    final isSpam = spam.isContentSpam == 'spam' || spam.score >= 3;
    final dominantEmotion = emotions.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    final summary = isSpam
        ? 'Spam detected • score ${spam.score} • ${spam.numberOfSpamWords} spam word(s)'
        : 'No spam • dominant emotion: $dominantEmotion';

    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id:            'chat-${DateTime.now().millisecondsSinceEpoch}',
            type:          'chat',
            title:         _controller.text.length > 60
                               ? '${_controller.text.substring(0, 60)}...'
                               : _controller.text,
            resultSummary: summary,
            date:          DateTime.now(),
            risk:          risk,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan WhatsApp / Telegram chats',
                subtitle:
                    'Analyze emotional tone and detect spam or threatening content',
              ),
              const SizedBox(height: 16),

              // ── Input card ──────────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _controller,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: 'Paste exported chat text here...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _runScan,
                            icon: const Icon(Icons.science),
                            label: Text(
                                _loading ? 'Scanning...' : 'Run analyzers'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    _controller.text =
                                        'URGENT: Your bank account has been suspended.\n'
                                        'Verify immediately at: http://secure-bank-verify.info\n'
                                        'I feel really scared and sad about this message.';
                                  },
                            child: const Text('Load demo chat'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Loading status ──────────────────────────────────────────────
              if (_loading && _statusMessage != null)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_statusMessage!,
                              style:
                                  TextStyle(color: Colors.blue.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Error ───────────────────────────────────────────────────────
              if (_errorMessage != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!,
                              style:
                                  TextStyle(color: Colors.red.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Results ─────────────────────────────────────────────────────
              if (_emotions != null && _spamResult != null) ...[
                const SizedBox(height: 4),
                _buildOverallVerdict(_emotions!, _spamResult!),
                const SizedBox(height: 12),
                _buildSpamCard(context, _spamResult!),
                const SizedBox(height: 12),
                _buildEmotionCard(context, _emotions!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Overall verdict banner ────────────────────────────────────────────────

  Widget _buildOverallVerdict(
      Map<String, double> emotions, SpamResult spam) {
    final risk = _computeRisk(emotions, spam);

    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    switch (risk) {
      case RiskLevel.high:
        bg       = Colors.red.shade50;
        fg       = Colors.red.shade800;
        icon     = Icons.gpp_bad;
        title    = 'High Risk Content';
        subtitle = 'Spam or threatening content detected. Parent notified.';
        break;
      case RiskLevel.medium:
        bg       = Colors.orange.shade50;
        fg       = Colors.orange.shade800;
        icon     = Icons.gpp_maybe;
        title    = 'Medium Risk Content';
        subtitle = 'Suspicious indicators found. Review recommended.';
        break;
      case RiskLevel.low:
        bg       = Colors.green.shade50;
        fg       = Colors.green.shade800;
        icon     = Icons.verified_user;
        title    = 'Low Risk Content';
        subtitle = 'No spam or significant threats detected.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(color: fg, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Spam result card ──────────────────────────────────────────────────────

  Widget _buildSpamCard(BuildContext context, SpamResult spam) {
    final isSpam  = spam.isContentSpam == 'spam' || spam.score >= 3;
    final color   = isSpam ? Colors.red : Colors.green;
    final scoreColor = spam.score >= 3
        ? Colors.red
        : spam.score == 2
            ? Colors.orange
            : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined,
                    color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('Spam Analysis',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // Score meter
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spam Score',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (spam.score / 5).clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${spam.score}/5',
                    style: TextStyle(
                        color: scoreColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Verdict row
            _buildResultRow(
              context,
              'Verdict',
              isSpam ? 'SPAM' : 'NOT SPAM',
              color,
            ),
            if (spam.numberOfSpamWords > 0) ...[
              const SizedBox(height: 8),
              _buildResultRow(
                context,
                'Spam words found',
                spam.numberOfSpamWords.toString(),
                Colors.orange,
              ),
            ],

            // Spam words chips
            if (spam.spamWords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Flagged words',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: spam.spamWords
                    .map((word) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(word,
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Emotion result card ───────────────────────────────────────────────────

  Widget _buildEmotionCard(
      BuildContext context, Map<String, double> emotions) {
    // Sort by score descending
    final sorted = emotions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final dominant = sorted.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('Emotion Analysis',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Dominant emotion: ${dominant.key} (${(dominant.value * 100).toStringAsFixed(0)}%)',
              style: TextStyle(
                  fontSize: 13,
                  color: _getEmotionColor(dominant.key),
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...sorted.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              _emotionEmoji(entry.key),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 6),
                            Text(entry.key,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w500)),
                          ],
                        ),
                        Text(
                          '${(entry.value * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: _getEmotionColor(entry.key),
                                  fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entry.value,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getEmotionColor(entry.key),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _buildResultRow(
      BuildContext context, String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: valueColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
      ],
    );
  }

  // ── Color and emoji helpers ───────────────────────────────────────────────

  Color _getEmotionColor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
      case 'joy':
      case 'surprise':
        return Colors.green;
      case 'sad':
      case 'sadness':
        return Colors.blue;
      case 'angry':
      case 'anger':
        return Colors.red;
      case 'fear':
      case 'anxiety':
        return Colors.orange;
      case 'disgust':
        return Colors.purple;
      case 'neutral':
        return Colors.grey;
      default:
        return AppTheme.accent;
    }
  }

  String _emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':   return '😊';
      case 'sad':     return '😢';
      case 'angry':   return '😠';
      case 'fear':    return '😨';
      case 'surprise':return '😲';
      case 'disgust': return '🤢';
      case 'neutral': return '😐';
      default:        return '🔹';
    }
  }
}

// ── Spam result model ─────────────────────────────────────────────────────────

class SpamResult {
  SpamResult({
    required this.score,
    required this.isContentSpam,
    required this.numberOfSpamWords,
    required this.spamWords,
  });

  final int score;
  final String isContentSpam;
  final int numberOfSpamWords;
  final List<String> spamWords;
}