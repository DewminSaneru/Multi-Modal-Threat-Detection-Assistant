import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

// ── API Configuration ─────────────────────────────────────────────────────────
const String _apiUrl = 'http://143.198.213.108:8000/predict';

// ── Response Model ────────────────────────────────────────────────────────────

class MLScanResult {
  MLScanResult({
    required this.filename,
    required this.predictedClass,
    required this.confidence,
    required this.safetyStatus,
    required this.safetyAction,
    required this.safetyMessage,
    required this.allScores,
  });

  final String filename;
  final String predictedClass;
  final double confidence;
  final String safetyStatus;   // SAFE | WARNING | BLOCKED | REVIEW
  final String safetyAction;   // allow | flag | block | review
  final String safetyMessage;
  final Map<String, double> allScores;

  factory MLScanResult.fromJson(Map<String, dynamic> json) {
    double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

    final safety = json['safety'] as Map<String, dynamic>? ?? {};
    final rawScores = json['all_scores'] as Map<String, dynamic>? ?? {};

    return MLScanResult(
      filename:      json['filename'] as String? ?? '',
      predictedClass: json['predicted_class'] as String? ?? 'unknown',
      confidence:    _d(json['confidence']),
      safetyStatus:  safety['status'] as String? ?? 'REVIEW',
      safetyAction:  safety['action'] as String? ?? 'review',
      safetyMessage: safety['message'] as String? ?? '',
      allScores:     rawScores.map((k, v) => MapEntry(k, _d(v))),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MediaScannerScreen extends ConsumerStatefulWidget {
  const MediaScannerScreen({super.key});

  @override
  ConsumerState<MediaScannerScreen> createState() => _MediaScannerScreenState();
}

class _MediaScannerScreenState extends ConsumerState<MediaScannerScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  String? _fileName;
  String? _errorMessage;
  String? _statusMessage;
  MLScanResult? _result;

  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Pick and scan ─────────────────────────────────────────────────────────

  Future<void> _pickAndScan() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    if (file.bytes == null) {
      setState(() => _errorMessage = 'Could not read file. Please try again.');
      return;
    }

    setState(() {
      _loading       = true;
      _errorMessage  = null;
      _result        = null;
      _fileName      = file.name;
      _statusMessage = 'Uploading image to scanner...';
    });
    _animController.reset();

    try {
      final result = await _scanImage(
        fileName:  file.name,
        fileBytes: file.bytes!,
      );

      setState(() {
        _result        = result;
        _loading       = false;
        _statusMessage = null;
      });
      _animController.forward();
      _addToHistory(result);
    } catch (e) {
      setState(() {
        _loading       = false;
        _statusMessage = null;
        _errorMessage  = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Call ML API ───────────────────────────────────────────────────────────

  Future<MLScanResult> _scanImage({
    required String fileName,
    required List<int> fileBytes,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
    ));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('API error (status ${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MLScanResult.fromJson(decoded);
  }

  // ── Add to history ────────────────────────────────────────────────────────

  void _addToHistory(MLScanResult result) {
    final risk = _toRiskLevel(result.safetyStatus);
    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id:            'media-${DateTime.now().millisecondsSinceEpoch}',
            type:          'image',
            title:         _fileName ?? 'Image',
            resultSummary: '${result.predictedClass.toUpperCase()} — ${result.safetyStatus}',
            date:          DateTime.now(),
            risk:          risk,
          ),
        );
  }

  RiskLevel _toRiskLevel(String status) {
    switch (status) {
      case 'BLOCKED': return RiskLevel.high;
      case 'WARNING': return RiskLevel.medium;
      default:        return RiskLevel.low;
    }
  }

  // ── Verdict config ────────────────────────────────────────────────────────

  _VerdictConfig _verdictConfig(MLScanResult r) {
    switch (r.safetyStatus) {
      case 'BLOCKED':
        return _VerdictConfig(
          bg: const Color(0xFFFFF0F0),
          fg: const Color(0xFFC0392B),
          border: const Color(0xFFE74C3C),
          icon: Icons.gpp_bad_rounded,
          badge: 'BLOCKED',
          badgeBg: const Color(0xFFE74C3C),
        );
      case 'WARNING':
        return _VerdictConfig(
          bg: const Color(0xFFFFF8EC),
          fg: const Color(0xFFB7570A),
          border: const Color(0xFFF39C12),
          icon: Icons.gpp_maybe_rounded,
          badge: 'WARNING',
          badgeBg: const Color(0xFFF39C12),
        );
      case 'REVIEW':
        return _VerdictConfig(
          bg: const Color(0xFFF0F4FF),
          fg: const Color(0xFF2C3E8C),
          border: const Color(0xFF3B5BDB),
          icon: Icons.manage_search_rounded,
          badge: 'REVIEW',
          badgeBg: const Color(0xFF3B5BDB),
        );
      default: // SAFE
        return _VerdictConfig(
          bg: const Color(0xFFF0FFF4),
          fg: const Color(0xFF1A6B3A),
          border: const Color(0xFF27AE60),
          icon: Icons.verified_user_rounded,
          badge: 'SAFE',
          badgeBg: const Color(0xFF27AE60),
        );
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan sensitive media',
                subtitle:
                    'Upload images to detect explicit, violent, or inappropriate content using AI.',
              ),
              const SizedBox(height: 16),

              // ── Upload card ───────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select an image to scan',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickAndScan,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: Text(
                            _loading ? 'Scanning...' : 'Choose & Scan Image'),
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.image_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_fileName!,
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[700]),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Loading ───────────────────────────────────────────────────
              if (_loading)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_statusMessage ?? 'Processing...',
                              style: TextStyle(color: Colors.blue.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Error ─────────────────────────────────────────────────────
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
                              style: TextStyle(color: Colors.red.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Results ───────────────────────────────────────────────────
              if (_result != null)
                FadeTransition(
                  opacity: _fadeIn,
                  child: Column(
                    children: [
                      _buildVerdictCard(_result!),
                      const SizedBox(height: 12),
                      _buildConfidenceCard(context, _result!),
                      const SizedBox(height: 12),
                      _buildAllScoresCard(context, _result!),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Verdict card ──────────────────────────────────────────────────────────

  Widget _buildVerdictCard(MLScanResult r) {
    final cfg = _verdictConfig(r);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cfg.icon, color: cfg.fg, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge + class
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: cfg.badgeBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(cfg.badge,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cfg.fg.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(r.predictedClass.toUpperCase(),
                          style: TextStyle(
                              color: cfg.fg,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(r.safetyMessage,
                    style: TextStyle(
                        color: cfg.fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Confidence card ───────────────────────────────────────────────────────

  Widget _buildConfidenceCard(BuildContext context, MLScanResult r) {
    final cfg = _verdictConfig(r);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('Prediction Confidence',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Big percentage circle
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: r.confidence,
                        strokeWidth: 7,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(cfg.badgeBg),
                      ),
                      Text('${(r.confidence * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: cfg.fg)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detected as',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 2),
                      Text(r.predictedClass.toUpperCase(),
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: cfg.fg)),
                      const SizedBox(height: 4),
                      Text(r.filename,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── All scores card ───────────────────────────────────────────────────────

  Widget _buildAllScoresCard(BuildContext context, MLScanResult r) {
    // Sort scores descending
    final sorted = r.allScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('All Class Scores',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ...sorted.map((entry) {
              final isTop = entry.key == r.predictedClass;
              final color = _scoreColor(entry.key, entry.value);
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
                              _classLabel(entry.key),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isTop
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isTop ? color : null),
                            ),
                            if (isTop) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('TOP',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: color)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${(entry.value * 100).toStringAsFixed(2)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entry.value.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            color.withOpacity(isTop ? 1.0 : 0.6)),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _scoreColor(String className, double value) {
    // Explicit classes are always red when high
    if (['porn', 'hentai'].contains(className) && value > 0.3) {
      return Colors.red;
    }
    if (className == 'sexy' && value > 0.4) return Colors.orange;
    if (className == 'neutral') return Colors.green;
    if (value > 0.6) return Colors.red;
    if (value > 0.3) return Colors.orange;
    return Colors.green;
  }

  String _classLabel(String className) {
  const labels = {
    'drawings': '🎨  Drawings',
    'hentai':   '🔞  Hentai',
    'neutral':  '✅  Neutral',
    'porn':     '🚫  Porn',
    'sexy':     '⚠️  Sexy',
    'violence': '🩸  Violence',   // add this line
  };
  return labels[className] ?? className.toUpperCase();
}
}

// ── Verdict config helper ─────────────────────────────────────────────────────

class _VerdictConfig {
  const _VerdictConfig({
    required this.bg,
    required this.fg,
    required this.border,
    required this.icon,
    required this.badge,
    required this.badgeBg,
  });
  final Color bg;
  final Color fg;
  final Color border;
  final IconData icon;
  final String badge;
  final Color badgeBg;
}