import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';

const String _apiUser   = '820797570';
const String _apiSecret = 'xsSbCHfdJdXvosfMiDBuZPS7bZTeKzGx';
const String _apiUrl    = 'https://api.sightengine.com/1.0/check.json';

// MethodChannel must match the one in MainActivity.kt
const _channel = MethodChannel('com.threatapp/share');

class SharedImageScanScreen extends ConsumerStatefulWidget {
  const SharedImageScanScreen({super.key});

  @override
  ConsumerState<SharedImageScanScreen> createState() =>
      _SharedImageScanScreenState();
}

class _SharedImageScanScreenState
    extends ConsumerState<SharedImageScanScreen> {
  bool _loading = true;
  String? _errorMessage;
  String? _imagePath;
  _ScanResult? _result;

  @override
  void initState() {
    super.initState();
    _receiveSharedImage();
  }

  // ── Get path from native Android via MethodChannel ────────────────────────

  Future<void> _receiveSharedImage() async {
    try {
      final path =
          await _channel.invokeMethod<String>('getSharedImagePath');

      if (path == null || path.isEmpty) {
        setState(() {
          _loading      = false;
          _errorMessage = 'No image was received.';
        });
        return;
      }

      setState(() => _imagePath = path);
      await _scanImage(path);
    } catch (e) {
      setState(() {
        _loading      = false;
        _errorMessage = 'Failed to receive image: $e';
      });
    }
  }

  // ── Scan via Sightengine ──────────────────────────────────────────────────

  Future<void> _scanImage(String filePath) async {
    setState(() {
      _loading      = true;
      _errorMessage = null;
    });

    try {
      final file      = File(filePath);
      final fileBytes = await file.readAsBytes();
      final fileName  = filePath.split('/').last;

      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.fields['models']     = 'nudity,wad,offensive';
      request.fields['api_user']   = _apiUser;
      request.fields['api_secret'] = _apiSecret;
      request.files.add(http.MultipartFile.fromBytes(
        'media',
        fileBytes,
        filename: fileName,
      ));

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception(
            'Sightengine error (status ${response.statusCode})');
      }

      final decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (decoded['status'] != 'success') {
        throw Exception(
            decoded['error']?['message'] ?? 'Unknown API error');
      }

      final result = _parseResult(decoded, fileName);
      _addToHistory(result, fileName);

      setState(() {
        _result  = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading      = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Parse + compute risk ──────────────────────────────────────────────────

  _ScanResult _parseResult(Map<String, dynamic> json, String fileName) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

    final nudity    = json['nudity']    as Map<String, dynamic>? ?? {};
    final offensive = json['offensive'] as Map<String, dynamic>? ?? {};

    final nudityRaw     = d(nudity['raw']);
    final weapon        = d(json['weapon']);
    final offensiveProb = d(offensive['prob']);
    final drugs         = d(json['drugs']);

    RiskLevel risk;
    if (nudityRaw > 0.7 || weapon > 0.7 ||
        offensiveProb > 0.7 || drugs > 0.7) {
      risk = RiskLevel.high;
    } else if (nudityRaw > 0.4 || weapon > 0.4 ||
               offensiveProb > 0.4 || drugs > 0.4) {
      risk = RiskLevel.medium;
    } else {
      risk = RiskLevel.low;
    }

    final flags = <String>[];
    if (nudityRaw > 0.4)     flags.add('Nudity (${_pct(nudityRaw)})');
    if (weapon > 0.4)        flags.add('Weapon (${_pct(weapon)})');
    if (offensiveProb > 0.4) flags.add('Offensive (${_pct(offensiveProb)})');
    if (drugs > 0.4)         flags.add('Drugs (${_pct(drugs)})');

    return _ScanResult(
      fileName:   fileName,
      risk:       risk,
      isSafe:     risk == RiskLevel.low,
      summary:    flags.isEmpty ? 'No threats detected' : flags.join(' • '),
      nudityRaw:  nudityRaw,
      weapon:     weapon,
      offensive:  offensiveProb,
      drugs:      drugs,
    );
  }

  void _addToHistory(_ScanResult result, String fileName) {
    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id:            'image-${DateTime.now().millisecondsSinceEpoch}',
            type:          'image',
            title:         fileName,
            resultSummary: result.summary,
            date:          DateTime.now(),
            risk:          result.risk,
          ),
        );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Safety Check'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? _buildLoading()
              : _errorMessage != null
                  ? _buildError()
                  : _buildResult(),
        ),
      ),
    );
  }

  Widget _buildLoading() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Scanning image for safety...',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text('Checking for nudity, weapons, and offensive content',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[500]),
                textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Scan Failed',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.red)),
            const SizedBox(height: 8),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Widget _buildResult() {
    final r = _result!;
    return ListView(
      children: [
        if (_imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_imagePath!),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 16),
        _buildVerdictBanner(r),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.analytics_outlined,
                      color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text('Detailed Scores',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                _buildScoreRow('Nudity',    r.nudityRaw),
                _buildScoreRow('Weapon',    r.weapon),
                _buildScoreRow('Offensive', r.offensive),
                _buildScoreRow('Drugs',     r.drugs),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Safe / Blocked message
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: r.isSafe ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: r.isSafe
                    ? Colors.green.shade200
                    : Colors.red.shade200),
          ),
          child: Column(
            children: [
              Icon(
                r.isSafe ? Icons.check_circle : Icons.block,
                color: r.isSafe ? Colors.green : Colors.red,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                r.isSafe
                    ? 'This image is safe to send'
                    : 'Sending Blocked',
                style: TextStyle(
                    color: r.isSafe
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                r.isSafe
                    ? 'No threats detected. You may proceed to send this image.'
                    : 'This image contains sensitive content. Your parent has been notified.',
                style: TextStyle(
                    color: r.isSafe
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildVerdictBanner(_ScanResult r) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;

    switch (r.risk) {
      case RiskLevel.high:
        bg = Colors.red.shade50; fg = Colors.red.shade800;
        icon = Icons.gpp_bad;
        title = 'High Risk — ${r.summary}';
        break;
      case RiskLevel.medium:
        bg = Colors.orange.shade50; fg = Colors.orange.shade800;
        icon = Icons.gpp_maybe;
        title = 'Medium Risk — ${r.summary}';
        break;
      case RiskLevel.low:
        bg = Colors.green.shade50; fg = Colors.green.shade800;
        icon = Icons.verified_user;
        title = 'Safe — No threats detected';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, double value) {
    final color = value > 0.7
        ? Colors.red
        : value > 0.4
            ? Colors.orange
            : Colors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(_pct(value),
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

class _ScanResult {
  const _ScanResult({
    required this.fileName,
    required this.risk,
    required this.isSafe,
    required this.summary,
    required this.nudityRaw,
    required this.weapon,
    required this.offensive,
    required this.drugs,
  });

  final String    fileName;
  final RiskLevel risk;
  final bool      isSafe;
  final String    summary;
  final double    nudityRaw;
  final double    weapon;
  final double    offensive;
  final double    drugs;
}