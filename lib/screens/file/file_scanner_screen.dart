import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

class FileScannerScreen extends ConsumerStatefulWidget {
  const FileScannerScreen({super.key});

  @override
  ConsumerState<FileScannerScreen> createState() => _FileScannerScreenState();
}

class _FileScannerScreenState extends ConsumerState<FileScannerScreen> {
  // ── API Config ────────────────────────────────────────────────────────────
  static const String _apiBase = 'http://129.212.238.212';

  // ── State ─────────────────────────────────────────────────────────────────
  bool _loading = false;
  String? _errorMessage;
  String? _statusMessage;
  ModelScanResult? _result;

  Future<void> _pickAndScanFile() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    if (file.bytes == null) {
      setState(() => _errorMessage = 'Could not read file bytes.');
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
      _errorMessage = null;
      _statusMessage = 'Uploading file for analysis...';
    });

    try {
      final result = await _scanFile(
        fileName: file.name,
        fileBytes: file.bytes!,
      );

      setState(() {
        _result = result;
        _loading = false;
        _statusMessage = null;
      });

      _addToHistory(result);
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = null;
        _errorMessage = 'Scan failed: ${e.toString()}';
      });
    }
  }

  Future<ModelScanResult> _scanFile({
    required String fileName,
    required List<int> fileBytes,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/scan'),
    );

    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
        'Server error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ModelScanResult.fromJson(json);
  }

  void _addToHistory(ModelScanResult result) {
    final risk = result.riskLevel == 'HIGH'
        ? RiskLevel.high
        : result.riskLevel == 'MEDIUM'
            ? RiskLevel.medium
            : RiskLevel.low;

    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id: 'file-${DateTime.now().millisecondsSinceEpoch}',
            type: 'file',
            title: result.filename,
            resultSummary:
                '${result.prediction} • ${result.confidence}% confidence',
            date: DateTime.now(),
            risk: risk,
          ),
        );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan files for malware',
                subtitle:
                    'Upload PDFs, EXE, APK, ZIP, DOCX and more for AI-powered threat detection.',
              ),
              const SizedBox(height: 16),

              // ── Upload Card ────────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select a file to scan',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Supported: PDF, EXE, DOCX, XLSX, ZIP, APK, JS, PY, SH, PHP, HTML',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickAndScanFile,
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                            _loading ? 'Scanning...' : 'Choose & Scan File'),
                      ),
                      if (_result != null) ...[
                        const SizedBox(height: 12),
                        _infoRow(Icons.insert_drive_file, _result!.filename),
                        _infoRow(Icons.label_outline,
                            'Type: ${_result!.fileType.toUpperCase()}'),
                        _infoRow(Icons.data_usage,
                            'Size: ${_formatBytes(_result!.fileSizeBytes)}'),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Progress ───────────────────────────────────────────────────
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

              // ── Error ──────────────────────────────────────────────────────
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

              // ── Results ────────────────────────────────────────────────────
              if (_result != null) ...[
                const SizedBox(height: 12),
                _buildResultCard(context, _result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey[800]),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _buildResultCard(BuildContext context, ModelScanResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.security, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('Scan Results',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                _riskBadge(r.riskLevel),
              ],
            ),
            const Divider(height: 24),

            // Verdict Banner
            _verdictBanner(r),
            const SizedBox(height: 20),

            // Confidence + Probabilities
            _confidenceSection(context, r),
            const SizedBox(height: 20),

            // Extracted Features
            _featuresSection(context, r),
          ],
        ),
      ),
    );
  }

  Widget _riskBadge(String level) {
    final color = level == 'HIGH'
        ? Colors.red
        : level == 'MEDIUM'
            ? Colors.orange
            : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$level RISK',
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _verdictBanner(ModelScanResult r) {
    final isMalware = r.prediction == 'MALWARE';
    final bg = isMalware ? Colors.red.shade50 : Colors.green.shade50;
    final fg = isMalware ? Colors.red.shade800 : Colors.green.shade800;
    final icon = isMalware ? Icons.gpp_bad : Icons.verified_user;
    final title = isMalware ? 'Threat Detected' : 'No Threats Found';
    final subtitle = isMalware
        ? 'Our AI model classified this file as malware with ${r.confidence}% confidence.'
        : 'Our AI model classified this file as benign with ${r.confidence}% confidence.';

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

  Widget _confidenceSection(BuildContext context, ModelScanResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detection Probabilities',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _probabilityBar(
          label: 'Malware',
          value: r.probabilities['malware'] ?? 0,
          color: Colors.red,
        ),
        const SizedBox(height: 10),
        _probabilityBar(
          label: 'Benign',
          value: r.probabilities['benign'] ?? 0,
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        // Confidence chip
        Row(
          children: [
            const Icon(Icons.analytics_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Model confidence: ${r.confidence}%',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _probabilityBar({
    required String label,
    required double value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${value.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _featuresSection(BuildContext context, ModelScanResult r) {
    // Highlight only features with non-zero values as suspicious indicators
    final suspicious = r.extractedFeatures.entries
        .where((e) =>
            [
              'JS',
              'OpenAction',
              'Launch',
              'AA',
              'EmbeddedFile',
              'XFA',
              'URI',
              'Action',
              'AcroForm',
            ].contains(e.key) &&
            e.value > 0)
        .toList();

    final allFeatures = r.extractedFeatures.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Extracted Features',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${allFeatures.length} features analyzed by the model',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),

        // Suspicious indicators
        if (suspicious.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Suspicious Indicators',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.orange.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: suspicious
                      .map(
                        (e) => Chip(
                          label: Text('${e.key}: ${e.value}',
                              style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              Colors.orange.shade100,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 10),

        // Full feature table
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: allFeatures.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final isLast = i == allFeatures.length - 1;
              final isHighlighted = suspicious
                  .any((s) => s.key == e.key);

              return Column(
                children: [
                  Container(
                    color: isHighlighted
                        ? Colors.orange.shade50
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (isHighlighted)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6),
                                  child: Icon(Icons.warning_amber,
                                      size: 13,
                                      color: Colors.orange.shade600),
                                ),
                              Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  fontWeight: isHighlighted
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isHighlighted
                                      ? Colors.orange.shade800
                                      : Colors.grey[800],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            e.value.toString(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isHighlighted
                                  ? Colors.orange.shade800
                                  : (e.value > 0
                                      ? Colors.black87
                                      : Colors.grey[400]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast)
                    Divider(
                        height: 1,
                        color: Colors.grey.shade200),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class ModelScanResult {
  const ModelScanResult({
    required this.filename,
    required this.fileType,
    required this.fileSizeBytes,
    required this.prediction,
    required this.confidence,
    required this.probabilities,
    required this.riskLevel,
    required this.extractedFeatures,
  });

  final String filename;
  final String fileType;
  final int fileSizeBytes;
  final String prediction;      // "MALWARE" | "BENIGN"
  final double confidence;
  final Map<String, double> probabilities; // { "malware": 99.0, "benign": 1.0 }
  final String riskLevel;       // "HIGH" | "MEDIUM" | "LOW"
  final Map<String, num> extractedFeatures;

  factory ModelScanResult.fromJson(Map<String, dynamic> json) {
    final probs = (json['probabilities'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble()));

    final feats = (json['extracted_features'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, v as num));

    return ModelScanResult(
      filename: json['filename'] as String? ?? '',
      fileType: json['file_type'] as String? ?? 'unknown',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      prediction: json['prediction'] as String? ?? 'UNKNOWN',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      probabilities: probs,
      riskLevel: json['risk_level'] as String? ?? 'LOW',
      extractedFeatures: feats,
    );
  }
}