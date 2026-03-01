import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

class LinksScannerScreen extends ConsumerStatefulWidget {
  const LinksScannerScreen({super.key});

  @override
  ConsumerState<LinksScannerScreen> createState() => _LinksScannerScreenState();
}

class _LinksScannerScreenState extends ConsumerState<LinksScannerScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  VirusTotalUrlAnalysis? _analysis;
  String? _errorMessage;

  static const String _virusTotalApiBase = 'https://www.virustotal.com/api/v3';
  // NOTE: For production apps, avoid hard-coding API keys in source code.
  static const String _virusTotalApiKey =
      'ffaa0d2a2b695f81ab3e5376bdae03a943708e55b2edc3450ca50bacb2ff0239';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    final rawText = _controller.text;
    final urlToScan = rawText
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');

    if (urlToScan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one URL to scan.')),
      );
      return;
    }

    setState(() => _loading = true);
    setState(() {
      _analysis = null;
      _errorMessage = null;
    });

    try {
      final analysisId = await _submitUrlForAnalysis(urlToScan);
      final analysis = await _waitForAnalysisResult(analysisId);

      setState(() {
        _analysis = analysis;
        _loading = false;
      });

      _addToHistory(analysis);
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Failed to scan URL. ${e.toString()}';
      });
    }
  }

  void _addToHistory(VirusTotalUrlAnalysis analysis) {
    final risk = analysis.malicious > 0
        ? RiskLevel.high
        : (analysis.suspicious > 0 ? RiskLevel.medium : RiskLevel.low);
    final summary =
        '${analysis.malicious} malicious, ${analysis.harmless} harmless'
        '${analysis.suspicious > 0 ? ', ${analysis.suspicious} suspicious' : ''}';
    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id: 'url-${DateTime.now().millisecondsSinceEpoch}',
            type: 'url',
            title: analysis.url.isNotEmpty ? analysis.url : 'URL scan',
            resultSummary: summary,
            date: DateTime.now(),
            risk: risk,
          ),
        );
  }

  Future<String> _submitUrlForAnalysis(String url) async {
    final response = await http.post(
      Uri.parse('$_virusTotalApiBase/urls'),
      headers: {
        'x-apikey': _virusTotalApiKey,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'url': url},
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'VirusTotal URL submission failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final id = data?['id'];

    if (id is! String) {
      throw Exception('Unexpected VirusTotal response format (missing id).');
    }

    return id;
  }

  Future<VirusTotalUrlAnalysis> _waitForAnalysisResult(String id) async {
    const maxAttempts = 10;
    const delayBetweenAttempts = Duration(seconds: 2);

    VirusTotalUrlAnalysis? lastAnalysis;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      lastAnalysis = await _fetchAnalysis(id);

      if (lastAnalysis.status == 'completed') {
        return lastAnalysis;
      }

      await Future.delayed(delayBetweenAttempts);
    }

    // Return the last analysis even if it never reached "completed"
    if (lastAnalysis != null) {
      return lastAnalysis;
    }

    throw Exception('No analysis data returned from VirusTotal.');
  }

  Future<VirusTotalUrlAnalysis> _fetchAnalysis(String id) async {
    final response = await http.get(
      Uri.parse('$_virusTotalApiBase/analyses/$id'),
      headers: {
        'x-apikey': _virusTotalApiKey,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'VirusTotal analysis fetch failed with status ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Unexpected VirusTotal response format (missing data).');
    }

    final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
    final stats = attributes['stats'] as Map<String, dynamic>? ?? {};

    final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
    final harmless = (stats['harmless'] as num?)?.toInt() ?? 0;
    final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
    final undetected = (stats['undetected'] as num?)?.toInt() ?? 0;

    final resultsMap = attributes['results'] as Map<String, dynamic>? ?? {};

    final engines = <VirusTotalEngineResult>[];

    resultsMap.forEach((engineKey, value) {
      if (value is Map<String, dynamic>) {
        engines.add(
          VirusTotalEngineResult(
            engineName: value['engine_name'] as String? ?? engineKey,
            category: value['category'] as String? ?? 'unknown',
            method: value['method'] as String? ?? '',
            result: value['result'] as String? ?? '',
          ),
        );
      }
    });

    engines.sort((a, b) => _categoryRank(a.category).compareTo(
          _categoryRank(b.category),
        ));

    return VirusTotalUrlAnalysis(
      id: data['id'] as String? ?? id,
      url: attributes['url'] as String? ?? '',
      status: attributes['status'] as String? ?? 'unknown',
      malicious: malicious,
      harmless: harmless,
      suspicious: suspicious,
      undetected: undetected,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Links Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan URLs and links',
                subtitle: 'Paste or enter links to analyze for threats and malicious content',
              ),
              const SizedBox(height: 16),
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
                          hintText: 'Paste link(s) here...\nExample: https://example.com',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _runScan,
                            icon: const Icon(Icons.science),
                            label:
                                Text(_loading ? 'Scanning...' : 'Run analyzers'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () {
                              _controller.text =
                                  'https://example.com\n'
                                  'https://suspicious-site.com\n'
                                  'https://trusted-website.org';
                            },
                            child: const Text('Load demo links'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.red.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_analysis != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.security, color: AppTheme.accent),
                            const SizedBox(width: 8),
                            Text(
                              'Scan Results',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_analysis!.url.isNotEmpty) ...[
                          Text(
                            _analysis!.url,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _buildVerdictChip(_analysis!),
                        const SizedBox(height: 16),
                        _buildStatsSection(context, _analysis!),
                        const SizedBox(height: 16),
                        _buildEnginesSection(context, _analysis!),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerdictChip(VirusTotalUrlAnalysis analysis) {
    final hasMalicious = analysis.malicious > 0;
    final hasSuspicious = analysis.suspicious > 0;

    late final Color color;
    late final String label;

    if (hasMalicious) {
      color = Colors.red;
      label = 'Malicious content detected (${analysis.malicious} engine(s))';
    } else if (hasSuspicious) {
      color = Colors.orange;
      label =
          'Suspicious indicators found (${analysis.suspicious} engine(s))';
    } else {
      color = Colors.green;
      label = 'No engines flagged this URL as malicious';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasMalicious || hasSuspicious ? Icons.warning_amber : Icons.check,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(
    BuildContext context,
    VirusTotalUrlAnalysis analysis,
  ) {
    final total = analysis.totalEngines.toDouble();
    final stats = <_StatRow>[
      _StatRow(
        label: 'Malicious',
        count: analysis.malicious,
        color: Colors.red,
      ),
      _StatRow(
        label: 'Suspicious',
        count: analysis.suspicious,
        color: Colors.orange,
      ),
      _StatRow(
        label: 'Harmless',
        count: analysis.harmless,
        color: Colors.green,
      ),
      _StatRow(
        label: 'Undetected',
        count: analysis.undetected,
        color: Colors.grey,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detection statistics',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...stats.map((s) {
          final ratio = total > 0 ? s.count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.label,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${s.count} engine(s)',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(s.color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEnginesSection(
    BuildContext context,
    VirusTotalUrlAnalysis analysis,
  ) {
    if (analysis.engines.isEmpty) {
      return const SizedBox.shrink();
    }

    final enginesToShow = analysis.engines.length > 12
        ? analysis.engines.take(12).toList()
        : analysis.engines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Engine verdicts (${analysis.engines.length})',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...enginesToShow.map(
          (engine) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.shield,
              size: 18,
              color: _engineCategoryColor(engine.category),
            ),
            title: Text(
              engine.engineName,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${engine.category} • ${engine.result}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[700]),
            ),
          ),
        ),
        if (analysis.engines.length > enginesToShow.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${analysis.engines.length - enginesToShow.length} more engines...',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }

  Color _engineCategoryColor(String category) {
    switch (category) {
      case 'malicious':
        return Colors.red;
      case 'suspicious':
        return Colors.orange;
      case 'harmless':
        return Colors.green;
      case 'undetected':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

}

class VirusTotalUrlAnalysis {
  VirusTotalUrlAnalysis({
    required this.id,
    required this.url,
    required this.status,
    required this.malicious,
    required this.harmless,
    required this.suspicious,
    required this.undetected,
    required this.engines,
  });

  final String id;
  final String url;
  final String status;
  final int malicious;
  final int harmless;
  final int suspicious;
  final int undetected;
  final List<VirusTotalEngineResult> engines;

  int get totalEngines =>
      malicious + harmless + suspicious + undetected;
}

class VirusTotalEngineResult {
  VirusTotalEngineResult({
    required this.engineName,
    required this.category,
    required this.method,
    required this.result,
  });

  final String engineName;
  final String category;
  final String method;
  final String result;
}

class _StatRow {
  const _StatRow({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

