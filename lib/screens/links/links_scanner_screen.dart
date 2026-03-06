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
  UrlScanResult? _result;
  String? _errorMessage;

  static const String _scanApiUrl = 'http://139.59.103.26:5000/scan';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Extract first non-empty URL from input ────────────────────────────────

  String _extractUrl() {
    return _controller.text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  }

  // ── Run scan ──────────────────────────────────────────────────────────────

  Future<void> _runScan() async {
    final url = _extractUrl();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL to scan.')),
      );
      return;
    }

    setState(() {
      _loading      = true;
      _result       = null;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(_scanApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Server error (status ${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result  = UrlScanResult.fromJson(decoded);

      setState(() {
        _result  = result;
        _loading = false;
      });

      _addToHistory(result);
    } catch (e) {
      setState(() {
        _loading      = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── History ───────────────────────────────────────────────────────────────

  void _addToHistory(UrlScanResult result) {
    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id:            'url-${DateTime.now().millisecondsSinceEpoch}',
            type:          'url',
            title:         result.url,
            resultSummary: '${result.status} • Risk score ${result.riskScorePct}%',
            date:          DateTime.now(),
            risk:          result.riskLevel,
          ),
        );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
                subtitle:
                    'Paste a link to check if it is safe or malicious.',
              ),
              const SizedBox(height: 16),

              // ── Input card ────────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _controller,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText:
                              'Paste a URL here...\nExample: https://example.com',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _runScan,
                            icon: const Icon(Icons.search),
                            label: Text(
                                _loading ? 'Scanning...' : 'Scan URL'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () => _controller.text =
                                'https://www.google.com',
                            child: const Text('Demo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

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
                        Text('Analysing URL...',
                            style:
                                TextStyle(color: Colors.blue.shade800)),
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
                              style: TextStyle(
                                  color: Colors.red.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Results ───────────────────────────────────────────────────
              if (_result != null) ...[
                _buildVerdictBanner(_result!),
                const SizedBox(height: 12),
                _buildDetailsCard(context, _result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Verdict banner ────────────────────────────────────────────────────────

  Widget _buildVerdictBanner(UrlScanResult r) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    switch (r.riskLevel) {
      case RiskLevel.high:
        bg       = Colors.red.shade50;
        fg       = Colors.red.shade800;
        icon     = Icons.gpp_bad;
        title    = 'Malicious URL Detected';
        subtitle = 'This link is dangerous. Do not visit it. Parent notified.';
        break;
      case RiskLevel.medium:
        bg       = Colors.orange.shade50;
        fg       = Colors.orange.shade800;
        icon     = Icons.gpp_maybe;
        title    = 'Suspicious URL';
        subtitle = 'This link shows suspicious indicators. Proceed with caution.';
        break;
      case RiskLevel.low:
        bg       = Colors.green.shade50;
        fg       = Colors.green.shade800;
        icon     = Icons.verified_user;
        title    = 'URL Appears Safe';
        subtitle = 'No threats detected on this link.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 40),
          const SizedBox(width: 14),
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

  // ── Details card ──────────────────────────────────────────────────────────

  Widget _buildDetailsCard(BuildContext context, UrlScanResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined,
                    color: AppTheme.accent),
                const SizedBox(width: 8),
                Text('Scan Details',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // Scanned URL
            _buildInfoRow(context, 'URL', r.url, isUrl: true),
            const Divider(height: 24),

            // Status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r.status,
                    style: TextStyle(
                        color: r.statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Risk score meter
            Text('Risk Score',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: r.riskScore.clamp(0.0, 1.0),
                      minHeight: 14,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(r.statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${r.riskScorePct}%',
                  style: TextStyle(
                      color: r.statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Safe', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                Text('Malicious', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value,
      {bool isUrl = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isUrl ? Colors.blue[700] : Colors.grey[700],
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

// ── Result model ──────────────────────────────────────────────────────────────

class UrlScanResult {
  const UrlScanResult({
    required this.url,
    required this.status,
    required this.riskScore,
  });

  final String url;
  final String status;   // "SAFE" | "MALICIOUS"
  final double riskScore; // 0.0 – 1.0

  factory UrlScanResult.fromJson(Map<String, dynamic> json) {
    return UrlScanResult(
      url:       json['url']        as String? ?? '',
      status:    json['status']     as String? ?? 'UNKNOWN',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // Risk score as percentage string
  String get riskScorePct => (riskScore * 100).toStringAsFixed(0);

  // Map status → RiskLevel for history + parent email
  RiskLevel get riskLevel {
    if (status == 'MALICIOUS' || riskScore >= 0.7) return RiskLevel.high;
    if (riskScore >= 0.4)                           return RiskLevel.medium;
    return RiskLevel.low;
  }

  Color get statusColor {
    switch (riskLevel) {
      case RiskLevel.high:   return Colors.red;
      case RiskLevel.medium: return Colors.orange;
      case RiskLevel.low:    return Colors.green;
    }
  }
}