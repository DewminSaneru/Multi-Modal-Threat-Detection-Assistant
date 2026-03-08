// import 'dart:convert';
// import 'dart:io';

// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:http/http.dart' as http;

// import '../../models/detection_models.dart';
// import '../../providers/scanner_provider.dart';
// import '../../theme/app_theme.dart';
// import '../../widgets/section_header.dart';

// class FileScannerScreen extends ConsumerStatefulWidget {
//   const FileScannerScreen({super.key});

//   @override
//   ConsumerState<FileScannerScreen> createState() => _FileScannerScreenState();
// }

// class _FileScannerScreenState extends ConsumerState<FileScannerScreen> {
//   // ── API Config ────────────────────────────────────────────────────────────
//   static const String _apiBase = 'http://129.212.238.212';

//   // ── State ─────────────────────────────────────────────────────────────────
//   bool _loading = false;
//   String? _errorMessage;
//   String? _statusMessage;
//   ModelScanResult? _result;

//   Future<void> _pickAndScanFile() async {
//     final picked = await FilePicker.platform.pickFiles(withData: true);
//     if (picked == null || picked.files.isEmpty) return;

//     final file = picked.files.single;
//     if (file.bytes == null) {
//       setState(() => _errorMessage = 'Could not read file bytes.');
//       return;
//     }

//     setState(() {
//       _loading = true;
//       _result = null;
//       _errorMessage = null;
//       _statusMessage = 'Uploading file for analysis...';
//     });

//     try {
//       final result = await _scanFile(
//         fileName: file.name,
//         fileBytes: file.bytes!,
//       );

//       setState(() {
//         _result = result;
//         _loading = false;
//         _statusMessage = null;
//       });

//       _addToHistory(result);
//     } catch (e) {
//       setState(() {
//         _loading = false;
//         _statusMessage = null;
//         _errorMessage = 'Scan failed: ${e.toString()}';
//       });
//     }
//   }

//   Future<ModelScanResult> _scanFile({
//     required String fileName,
//     required List<int> fileBytes,
//   }) async {
//     final request = http.MultipartRequest(
//       'POST',
//       Uri.parse('$_apiBase/scan'),
//     );

//     request.files.add(
//       http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
//     );

//     final streamed = await request.send();
//     final response = await http.Response.fromStream(streamed);

//     if (response.statusCode != 200) {
//       throw Exception(
//         'Server error ${response.statusCode}: ${response.body}',
//       );
//     }

//     final json = jsonDecode(response.body) as Map<String, dynamic>;
//     return ModelScanResult.fromJson(json);
//   }

//   void _addToHistory(ModelScanResult result) {
//     final risk = result.riskLevel == 'HIGH'
//         ? RiskLevel.high
//         : result.riskLevel == 'MEDIUM'
//             ? RiskLevel.medium
//             : RiskLevel.low;

//     ref.read(scanHistoryNotifierProvider.notifier).addEntry(
//           ScanHistoryEntry(
//             id: 'file-${DateTime.now().millisecondsSinceEpoch}',
//             type: 'file',
//             title: result.filename,
//             resultSummary:
//                 '${result.prediction} • ${result.confidence}% confidence',
//             date: DateTime.now(),
//             risk: risk,
//           ),
//         );
//   }

//   String _formatBytes(int bytes) {
//     if (bytes < 1024) return '$bytes B';
//     if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
//     return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
//   }

//   // ── BUILD ──────────────────────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('File Scanner')),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: ListView(
//             children: [
//               const SectionHeader(
//                 title: 'Scan files for malware',
//                 subtitle:
//                     'Upload PDFs, EXE, APK, ZIP, DOCX and more for AI-powered threat detection.',
//               ),
//               const SizedBox(height: 16),

//               // ── Upload Card ────────────────────────────────────────────────
//               Card(
//                 child: Padding(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text('Select a file to scan',
//                           style: Theme.of(context).textTheme.titleMedium),
//                       const SizedBox(height: 4),
//                       Text(
//                         'Supported: PDF, EXE, DOCX, XLSX, ZIP, APK, JS, PY, SH, PHP, HTML',
//                         style: TextStyle(
//                             fontSize: 12, color: Colors.grey[600]),
//                       ),
//                       const SizedBox(height: 12),
//                       ElevatedButton.icon(
//                         onPressed: _loading ? null : _pickAndScanFile,
//                         icon: const Icon(Icons.upload_file),
//                         label: Text(
//                             _loading ? 'Scanning...' : 'Choose & Scan File'),
//                       ),
//                       if (_result != null) ...[
//                         const SizedBox(height: 12),
//                         _infoRow(Icons.insert_drive_file, _result!.filename),
//                         _infoRow(Icons.label_outline,
//                             'Type: ${_result!.fileType.toUpperCase()}'),
//                         _infoRow(Icons.data_usage,
//                             'Size: ${_formatBytes(_result!.fileSizeBytes)}'),
//                       ],
//                     ],
//                   ),
//                 ),
//               ),

//               const SizedBox(height: 12),

//               // ── Progress ───────────────────────────────────────────────────
//               if (_loading && _statusMessage != null)
//                 Card(
//                   color: Colors.blue.shade50,
//                   child: Padding(
//                     padding: const EdgeInsets.all(14),
//                     child: Row(
//                       children: [
//                         const SizedBox(
//                           width: 20,
//                           height: 20,
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         ),
//                         const SizedBox(width: 12),
//                         Expanded(
//                           child: Text(_statusMessage!,
//                               style:
//                                   TextStyle(color: Colors.blue.shade800)),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),

//               // ── Error ──────────────────────────────────────────────────────
//               if (_errorMessage != null)
//                 Card(
//                   color: Colors.red.shade50,
//                   child: Padding(
//                     padding: const EdgeInsets.all(14),
//                     child: Row(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Icon(Icons.error_outline, color: Colors.red),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: Text(_errorMessage!,
//                               style:
//                                   TextStyle(color: Colors.red.shade800)),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),

//               // ── Results ────────────────────────────────────────────────────
//               if (_result != null) ...[
//                 const SizedBox(height: 12),
//                 _buildResultCard(context, _result!),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ── Widgets ────────────────────────────────────────────────────────────────

//   Widget _infoRow(IconData icon, String text) => Padding(
//         padding: const EdgeInsets.only(top: 6),
//         child: Row(
//           children: [
//             Icon(icon, size: 16, color: Colors.grey[600]),
//             const SizedBox(width: 6),
//             Expanded(
//               child: Text(text,
//                   style:
//                       TextStyle(fontSize: 13, color: Colors.grey[800]),
//                   overflow: TextOverflow.ellipsis),
//             ),
//           ],
//         ),
//       );

//   Widget _buildResultCard(BuildContext context, ModelScanResult r) {
//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Header
//             Row(
//               children: [
//                 const Icon(Icons.security, color: AppTheme.accent),
//                 const SizedBox(width: 8),
//                 Text('Scan Results',
//                     style: Theme.of(context)
//                         .textTheme
//                         .titleMedium
//                         ?.copyWith(fontWeight: FontWeight.bold)),
//                 const Spacer(),
//                 _riskBadge(r.riskLevel),
//               ],
//             ),
//             const Divider(height: 24),

//             // Verdict Banner
//             _verdictBanner(r),
//             const SizedBox(height: 20),

//             // Confidence + Probabilities
//             _confidenceSection(context, r),
//             const SizedBox(height: 20),

//             // Extracted Features
//             _featuresSection(context, r),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _riskBadge(String level) {
//     final color = level == 'HIGH'
//         ? Colors.red
//         : level == 'MEDIUM'
//             ? Colors.orange
//             : Colors.green;
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.12),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: color.withOpacity(0.4)),
//       ),
//       child: Text(
//         '$level RISK',
//         style: TextStyle(
//             fontSize: 11, color: color, fontWeight: FontWeight.bold),
//       ),
//     );
//   }

//   Widget _verdictBanner(ModelScanResult r) {
//     final isMalware = r.prediction == 'MALWARE';
//     final bg = isMalware ? Colors.red.shade50 : Colors.green.shade50;
//     final fg = isMalware ? Colors.red.shade800 : Colors.green.shade800;
//     final icon = isMalware ? Icons.gpp_bad : Icons.verified_user;
//     final title = isMalware ? 'Threat Detected' : 'No Threats Found';
//     final subtitle = isMalware
//         ? 'Our AI model classified this file as malware with ${r.confidence}% confidence.'
//         : 'Our AI model classified this file as benign with ${r.confidence}% confidence.';

//     return Container(
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: bg,
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: Row(
//         children: [
//           Icon(icon, color: fg, size: 36),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(title,
//                     style: TextStyle(
//                         color: fg,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 16)),
//                 const SizedBox(height: 4),
//                 Text(subtitle,
//                     style: TextStyle(color: fg, fontSize: 13)),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _confidenceSection(BuildContext context, ModelScanResult r) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text('Detection Probabilities',
//             style: Theme.of(context)
//                 .textTheme
//                 .titleSmall
//                 ?.copyWith(fontWeight: FontWeight.w700)),
//         const SizedBox(height: 12),
//         _probabilityBar(
//           label: 'Malware',
//           value: r.probabilities['malware'] ?? 0,
//           color: Colors.red,
//         ),
//         const SizedBox(height: 10),
//         _probabilityBar(
//           label: 'Benign',
//           value: r.probabilities['benign'] ?? 0,
//           color: Colors.green,
//         ),
//         const SizedBox(height: 12),
//         // Confidence chip
//         Row(
//           children: [
//             const Icon(Icons.analytics_outlined, size: 16, color: Colors.grey),
//             const SizedBox(width: 6),
//             Text(
//               'Model confidence: ${r.confidence}%',
//               style: TextStyle(
//                   fontSize: 13,
//                   fontWeight: FontWeight.w600,
//                   color: Colors.grey[700]),
//             ),
//           ],
//         ),
//       ],
//     );
//   }

//   Widget _probabilityBar({
//     required String label,
//     required double value,
//     required Color color,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(label,
//                 style: const TextStyle(fontWeight: FontWeight.w500)),
//             Text('${value.toStringAsFixed(1)}%',
//                 style: TextStyle(fontSize: 12, color: Colors.grey[600])),
//           ],
//         ),
//         const SizedBox(height: 4),
//         ClipRRect(
//           borderRadius: BorderRadius.circular(4),
//           child: LinearProgressIndicator(
//             value: value / 100,
//             minHeight: 8,
//             backgroundColor: Colors.grey[200],
//             valueColor: AlwaysStoppedAnimation<Color>(color),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _featuresSection(BuildContext context, ModelScanResult r) {
//     // Highlight only features with non-zero values as suspicious indicators
//     final suspicious = r.extractedFeatures.entries
//         .where((e) =>
//             [
//               'JS',
//               'OpenAction',
//               'Launch',
//               'AA',
//               'EmbeddedFile',
//               'XFA',
//               'URI',
//               'Action',
//               'AcroForm',
//             ].contains(e.key) &&
//             e.value > 0)
//         .toList();

//     final allFeatures = r.extractedFeatures.entries.toList();

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text('Extracted Features',
//             style: Theme.of(context)
//                 .textTheme
//                 .titleSmall
//                 ?.copyWith(fontWeight: FontWeight.w700)),
//         const SizedBox(height: 4),
//         Text('${allFeatures.length} features analyzed by the model',
//             style: TextStyle(fontSize: 12, color: Colors.grey[600])),

//         // Suspicious indicators
//         if (suspicious.isNotEmpty) ...[
//           const SizedBox(height: 10),
//           Container(
//             padding: const EdgeInsets.all(10),
//             decoration: BoxDecoration(
//               color: Colors.orange.shade50,
//               borderRadius: BorderRadius.circular(8),
//               border:
//                   Border.all(color: Colors.orange.shade200),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Icon(Icons.warning_amber,
//                         size: 16, color: Colors.orange.shade700),
//                     const SizedBox(width: 6),
//                     Text(
//                       'Suspicious Indicators',
//                       style: TextStyle(
//                           fontWeight: FontWeight.w600,
//                           fontSize: 13,
//                           color: Colors.orange.shade700),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 8),
//                 Wrap(
//                   spacing: 6,
//                   runSpacing: 6,
//                   children: suspicious
//                       .map(
//                         (e) => Chip(
//                           label: Text('${e.key}: ${e.value}',
//                               style: const TextStyle(fontSize: 11)),
//                           backgroundColor:
//                               Colors.orange.shade100,
//                           padding: EdgeInsets.zero,
//                           materialTapTargetSize:
//                               MaterialTapTargetSize.shrinkWrap,
//                         ),
//                       )
//                       .toList(),
//                 ),
//               ],
//             ),
//           ),
//         ],

//         const SizedBox(height: 10),

//         // Full feature table
//         Container(
//           decoration: BoxDecoration(
//             border: Border.all(color: Colors.grey.shade200),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Column(
//             children: allFeatures.asMap().entries.map((entry) {
//               final i = entry.key;
//               final e = entry.value;
//               final isLast = i == allFeatures.length - 1;
//               final isHighlighted = suspicious
//                   .any((s) => s.key == e.key);

//               return Column(
//                 children: [
//                   Container(
//                     color: isHighlighted
//                         ? Colors.orange.shade50
//                         : null,
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 14, vertical: 9),
//                       child: Row(
//                         mainAxisAlignment:
//                             MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(
//                             children: [
//                               if (isHighlighted)
//                                 Padding(
//                                   padding:
//                                       const EdgeInsets.only(right: 6),
//                                   child: Icon(Icons.warning_amber,
//                                       size: 13,
//                                       color: Colors.orange.shade600),
//                                 ),
//                               Text(
//                                 e.key,
//                                 style: TextStyle(
//                                   fontSize: 13,
//                                   fontFamily: 'monospace',
//                                   fontWeight: isHighlighted
//                                       ? FontWeight.w600
//                                       : FontWeight.normal,
//                                   color: isHighlighted
//                                       ? Colors.orange.shade800
//                                       : Colors.grey[800],
//                                 ),
//                               ),
//                             ],
//                           ),
//                           Text(
//                             e.value.toString(),
//                             style: TextStyle(
//                               fontSize: 13,
//                               fontWeight: FontWeight.w600,
//                               color: isHighlighted
//                                   ? Colors.orange.shade800
//                                   : (e.value > 0
//                                       ? Colors.black87
//                                       : Colors.grey[400]),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                   if (!isLast)
//                     Divider(
//                         height: 1,
//                         color: Colors.grey.shade200),
//                 ],
//               );
//             }).toList(),
//           ),
//         ),
//       ],
//     );
//   }
// }

// // ─── Data Model ───────────────────────────────────────────────────────────────

// class ModelScanResult {
//   const ModelScanResult({
//     required this.filename,
//     required this.fileType,
//     required this.fileSizeBytes,
//     required this.prediction,
//     required this.confidence,
//     required this.probabilities,
//     required this.riskLevel,
//     required this.extractedFeatures,
//   });

//   final String filename;
//   final String fileType;
//   final int fileSizeBytes;
//   final String prediction;      // "MALWARE" | "BENIGN"
//   final double confidence;
//   final Map<String, double> probabilities; // { "malware": 99.0, "benign": 1.0 }
//   final String riskLevel;       // "HIGH" | "MEDIUM" | "LOW"
//   final Map<String, num> extractedFeatures;

//   factory ModelScanResult.fromJson(Map<String, dynamic> json) {
//     final probs = (json['probabilities'] as Map<String, dynamic>? ?? {})
//         .map((k, v) => MapEntry(k, (v as num).toDouble()));

//     final feats = (json['extracted_features'] as Map<String, dynamic>? ?? {})
//         .map((k, v) => MapEntry(k, v as num));

//     return ModelScanResult(
//       filename: json['filename'] as String? ?? '',
//       fileType: json['file_type'] as String? ?? 'unknown',
//       fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
//       prediction: json['prediction'] as String? ?? 'UNKNOWN',
//       confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
//       probabilities: probs,
//       riskLevel: json['risk_level'] as String? ?? 'LOW',
//       extractedFeatures: feats,
//     );
//   }
// }

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../widgets/section_header.dart';
import '../../theme/app_theme.dart';

class FileScannerScreen extends StatefulWidget {
  const FileScannerScreen({super.key});

  @override
  State<FileScannerScreen> createState() => _FileScannerScreenState();
}

class _FileScannerScreenState extends State<FileScannerScreen> {
  static const String _virusTotalApiBase = 'https://www.virustotal.com/api/v3';
  // NOTE: For production apps, avoid hard-coding API keys in source code.
  static const String _virusTotalApiKey =
      'ffaa0d2a2b695f81ab3e5376bdae03a943708e55b2edc3450ca50bacb2ff0239';

  bool _loading = false;
  String? _fileName;
  String? _fileExtension;
  int? _fileSizeBytes;
  String? _errorMessage;
  String? _statusMessage;
  VirusTotalFileAnalysis? _analysis;

  Future<void> _pickAndScanFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;

    if (file.bytes == null) {
      setState(() {
        _errorMessage = 'Could not read file bytes. Please try another file.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _fileName = file.name;
      _fileExtension = file.extension ?? 'unknown';
      _fileSizeBytes = file.size;
      _analysis = null;
      _errorMessage = null;
      _statusMessage = 'Uploading file to ML Model...';
    });

    try {
      final analysisId = await _uploadFile(
        fileName: file.name,
        fileBytes: file.bytes!,
        extension: file.extension ?? 'bin',
      );

      setState(() => _statusMessage = 'File uploaded. Waiting for analysis...');

      final analysis = await _waitForAnalysisResult(analysisId);

      setState(() {
        _analysis = analysis;
        _loading = false;
        _statusMessage = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = null;
        _errorMessage = 'Scan failed: ${e.toString()}';
      });
    }
  }

  Future<String> _uploadFile({
    required String fileName,
    required List<int> fileBytes,
    required String extension,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_virusTotalApiBase/files'),
    );

    request.headers['x-apikey'] = _virusTotalApiKey;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'ML model file upload failed with status ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final id = data?['id'];

    if (id is! String) {
      throw Exception('Unexpected ML model response (missing analysis id).');
    }

    return id;
  }

  Future<VirusTotalFileAnalysis> _waitForAnalysisResult(String id) async {
    const maxAttempts = 15;
    const delay = Duration(seconds: 3);

    VirusTotalFileAnalysis? last;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      last = await _fetchAnalysis(id);

      if (last.status == 'completed') {
        return last;
      }

      setState(() =>
          _statusMessage = 'Analyzing... (attempt ${attempt + 1}/$maxAttempts)');
      await Future.delayed(delay);
    }

    if (last != null) return last;
    throw Exception('Analysis did not complete in time.');
  }

  Future<VirusTotalFileAnalysis> _fetchAnalysis(String id) async {
    final response = await http.get(
      Uri.parse('$_virusTotalApiBase/analyses/$id'),
      headers: {'x-apikey': _virusTotalApiKey},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch analysis (status ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Unexpected response format (missing data).');
    }

    final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
    final stats = attributes['stats'] as Map<String, dynamic>? ?? {};
    final meta = (decoded['meta'] as Map<String, dynamic>? ?? {});
    final fileInfo = meta['file_info'] as Map<String, dynamic>? ?? {};

    final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
    final harmless = (stats['harmless'] as num?)?.toInt() ?? 0;
    final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
    final undetected = (stats['undetected'] as num?)?.toInt() ?? 0;
    final timeout = (stats['timeout'] as num?)?.toInt() ?? 0;
    final typeUnsupported = (stats['type-unsupported'] as num?)?.toInt() ?? 0;
    final confirmedTimeout =
        (stats['confirmed-timeout'] as num?)?.toInt() ?? 0;
    final failure = (stats['failure'] as num?)?.toInt() ?? 0;

    final resultsMap =
        attributes['results'] as Map<String, dynamic>? ?? {};

    final engines = <VirusTotalEngineResult>[];
    resultsMap.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        engines.add(VirusTotalEngineResult(
          engineName: value['engine_name'] as String? ?? key,
          engineVersion: value['engine_version'] as String? ?? '',
          category: value['category'] as String? ?? 'unknown',
          result: value['result'] as String? ?? '',
          method: value['method'] as String? ?? '',
          engineUpdate: value['engine_update'] as String? ?? '',
        ));
      }
    });

    engines.sort((a, b) =>
        _categoryRank(a.category).compareTo(_categoryRank(b.category)));

    return VirusTotalFileAnalysis(
      id: data['id'] as String? ?? id,
      status: attributes['status'] as String? ?? 'unknown',
      malicious: malicious,
      harmless: harmless,
      suspicious: suspicious,
      undetected: undetected,
      timeout: timeout,
      typeUnsupported: typeUnsupported,
      confirmedTimeout: confirmedTimeout,
      failure: failure,
      sha256: fileInfo['sha256'] as String? ?? '',
      md5: fileInfo['md5'] as String? ?? '',
      sha1: fileInfo['sha1'] as String? ?? '',
      engines: engines,
    );
  }

  int _categoryRank(String category) {
    switch (category) {
      case 'malicious':
        return 0;
      case 'suspicious':
        return 1;
      case 'harmless':
        return 2;
      case 'undetected':
        return 3;
      default:
        return 4;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

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
                    'Upload PDFs, EXE, APK, ZIP, DOCX and more to detect threats.',
              ),
              const SizedBox(height: 16),

              // ── Upload card ──────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select a file to scan',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickAndScanFile,
                        icon: const Icon(Icons.upload_file),
                        label:
                            Text(_loading ? 'Scanning...' : 'Choose & Scan File'),
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 12),
                        _buildFileInfoRow(
                            Icons.insert_drive_file, _fileName!),
                        if (_fileExtension != null)
                          _buildFileInfoRow(
                              Icons.label_outline,
                              'Type: ${_fileExtension!.toUpperCase()}'),
                        if (_fileSizeBytes != null)
                          _buildFileInfoRow(
                              Icons.data_usage,
                              'Size: ${_formatBytes(_fileSizeBytes!)}'),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Status / progress ────────────────────────────────────────
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
                              style: TextStyle(color: Colors.blue.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Error ────────────────────────────────────────────────────
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
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Results ──────────────────────────────────────────────────
              if (_analysis != null) ...[
                const SizedBox(height: 12),
                _buildResultsCard(context, _analysis!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard(
      BuildContext context, VirusTotalFileAnalysis analysis) {
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
                _buildStatusBadge(analysis.status),
              ],
            ),
            const Divider(height: 24),

            // Verdict
            _buildVerdictBanner(analysis),
            const SizedBox(height: 20),

            // Detection stats
            _buildDetectionStats(context, analysis),
            const SizedBox(height: 20),

            // File hashes
            if (analysis.sha256.isNotEmpty ||
                analysis.md5.isNotEmpty ||
                analysis.sha1.isNotEmpty) ...[
              _buildHashSection(context, analysis),
              const SizedBox(height: 20),
            ],

            // Engine results
            _buildEnginesSection(context, analysis),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color =
        status == 'completed' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerdictBanner(VirusTotalFileAnalysis analysis) {
    final isMalicious = analysis.malicious > 0;
    final isSuspicious = analysis.suspicious > 0;

    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    if (isMalicious) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
      icon = Icons.gpp_bad;
      title = 'Threat Detected';
      subtitle =
          '${analysis.malicious} out of ${analysis.totalSignificantEngines} security engines flagged this file as malicious.';
    } else if (isSuspicious) {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
      icon = Icons.gpp_maybe;
      title = 'Suspicious File';
      subtitle =
          '${analysis.suspicious} engine(s) found suspicious indicators.';
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      icon = Icons.verified_user;
      title = 'No Threats Found';
      subtitle = 'No security engines flagged this file as malicious.';
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

  Widget _buildDetectionStats(
      BuildContext context, VirusTotalFileAnalysis analysis) {
    final total = analysis.totalEngines.toDouble();

    final rows = [
      _StatRow('Malicious', analysis.malicious, Colors.red),
      _StatRow('Suspicious', analysis.suspicious, Colors.orange),
      _StatRow('Harmless', analysis.harmless, Colors.green),
      _StatRow('Undetected', analysis.undetected, Colors.grey),
      if (analysis.timeout > 0)
        _StatRow('Timeout', analysis.timeout, Colors.blueGrey),
      if (analysis.failure > 0)
        _StatRow('Failure', analysis.failure, Colors.purple),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detection Statistics',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          '${analysis.malicious + analysis.suspicious} / ${analysis.totalSignificantEngines} engines detected a threat',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        ...rows.map((row) {
          final ratio = total > 0 ? row.count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text('${row.count} engine(s)',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(row.color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildHashSection(
      BuildContext context, VirusTotalFileAnalysis analysis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('File Hashes',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (analysis.sha256.isNotEmpty)
                _buildHashRow('SHA-256', analysis.sha256),
              if (analysis.sha1.isNotEmpty) ...[
                const Divider(height: 16),
                _buildHashRow('SHA-1', analysis.sha1),
              ],
              if (analysis.md5.isNotEmpty) ...[
                const Divider(height: 16),
                _buildHashRow('MD5', analysis.md5),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHashRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildEnginesSection(
      BuildContext context, VirusTotalFileAnalysis analysis) {
    if (analysis.engines.isEmpty) return const SizedBox.shrink();

    // Show flagging engines first, then up to 12 total
    final flagged = analysis.engines
        .where((e) =>
            e.category == 'malicious' || e.category == 'suspicious')
        .toList();
    final others = analysis.engines
        .where((e) =>
            e.category != 'malicious' && e.category != 'suspicious')
        .take((12 - flagged.length).clamp(0, 12))
        .toList();
    final toShow = [...flagged, ...others];
    final remaining = analysis.engines.length - toShow.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Engine Verdicts (${analysis.engines.length} total)',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: toShow.asMap().entries.map((entry) {
              final i = entry.key;
              final engine = entry.value;
              final isLast = i == toShow.length - 1 && remaining == 0;
              return Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          _categoryColor(engine.category).withOpacity(0.15),
                      child: Icon(
                        _categoryIcon(engine.category),
                        size: 14,
                        color: _categoryColor(engine.category),
                      ),
                    ),
                    title: Text(engine.engineName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          engine.result.isNotEmpty
                              ? engine.result
                              : engine.category,
                          style: TextStyle(
                              color: _categoryColor(engine.category),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                        if (engine.engineVersion.isNotEmpty)
                          Text('v${engine.engineVersion}  •  Updated ${engine.engineUpdate}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                    trailing: _buildCategoryChip(engine.category),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          ),
        ),
        if (remaining > 0) ...[
          const SizedBox(height: 6),
          Text(
            '+ $remaining more engine(s) not shown',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryChip(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _categoryColor(category).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        category,
        style: TextStyle(
            fontSize: 11,
            color: _categoryColor(category),
            fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'malicious':
        return Colors.red;
      case 'suspicious':
        return Colors.orange;
      case 'harmless':
        return Colors.green;
      case 'undetected':
        return Colors.grey;
      case 'timeout':
        return Colors.blueGrey;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'malicious':
        return Icons.dangerous;
      case 'suspicious':
        return Icons.warning_amber;
      case 'harmless':
        return Icons.check_circle;
      case 'undetected':
        return Icons.help_outline;
      default:
        return Icons.shield;
    }
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

class VirusTotalFileAnalysis {
  VirusTotalFileAnalysis({
    required this.id,
    required this.status,
    required this.malicious,
    required this.harmless,
    required this.suspicious,
    required this.undetected,
    required this.timeout,
    required this.typeUnsupported,
    required this.confirmedTimeout,
    required this.failure,
    required this.sha256,
    required this.md5,
    required this.sha1,
    required this.engines,
  });

  final String id;
  final String status;
  final int malicious;
  final int harmless;
  final int suspicious;
  final int undetected;
  final int timeout;
  final int typeUnsupported;
  final int confirmedTimeout;
  final int failure;
  final String sha256;
  final String md5;
  final String sha1;
  final List<VirusTotalEngineResult> engines;

  int get totalEngines =>
      malicious + harmless + suspicious + undetected + timeout + failure;

  /// Engines that gave a conclusive verdict (excludes unsupported/timeout/failure)
  int get totalSignificantEngines => malicious + harmless + suspicious + undetected;
}

class VirusTotalEngineResult {
  VirusTotalEngineResult({
    required this.engineName,
    required this.engineVersion,
    required this.category,
    required this.result,
    required this.method,
    required this.engineUpdate,
  });

  final String engineName;
  final String engineVersion;
  final String category;
  final String result;
  final String method;
  final String engineUpdate;
}

class _StatRow {
  const _StatRow(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}