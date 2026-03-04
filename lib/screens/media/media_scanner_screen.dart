import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

class MediaScannerScreen extends ConsumerStatefulWidget {
  const MediaScannerScreen({super.key});

  @override
  ConsumerState<MediaScannerScreen> createState() => _MediaScannerScreenState();
}

class _MediaScannerScreenState extends ConsumerState<MediaScannerScreen> {
  // ── Sightengine credentials ───────────────────────────────────────────────
  static const String _apiUser   = '820797570';
  static const String _apiSecret = 'xsSbCHfdJdXvosfMiDBuZPS7bZTeKzGx';
  static const String _apiUrl    = 'https://api.sightengine.com/1.0/check.json';

  bool _loading = false;
  String? _fileName;
  String? _errorMessage;
  String? _statusMessage;
  SightengineResult? _result;

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
      _statusMessage = 'Uploading image to Sightengine...';
    });

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

      _addToHistory(result);
    } catch (e) {
      setState(() {
        _loading       = false;
        _statusMessage = null;
        _errorMessage  = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Call Sightengine API ──────────────────────────────────────────────────

  Future<SightengineResult> _scanImage({
    required String fileName,
    required List<int> fileBytes,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

    request.fields['models']     = 'nudity,wad,offensive';
    request.fields['api_user']   = _apiUser;
    request.fields['api_secret'] = _apiSecret;

    request.files.add(http.MultipartFile.fromBytes(
      'media',
      fileBytes,
      filename: fileName,
    ));

    final streamed  = await request.send().timeout(const Duration(seconds: 30));
    final response  = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Sightengine API failed (status ${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (decoded['status'] != 'success') {
      final error = decoded['error']?['message'] ?? 'Unknown API error';
      throw Exception(error);
    }

    return SightengineResult.fromJson(decoded);
  }

  // ── Compute risk from result ──────────────────────────────────────────────

  RiskLevel _computeRisk(SightengineResult r) {
    // High: nudity raw > 0.7, weapon > 0.7, offensive > 0.7, drugs > 0.7
    if (r.nudityRaw > 0.7 ||
        r.weapon > 0.7 ||
        r.offensiveProb > 0.7 ||
        r.drugs > 0.7) {
      return RiskLevel.high;
    }
    // Medium: any of the above > 0.4
    if (r.nudityRaw > 0.4 ||
        r.weapon > 0.4 ||
        r.offensiveProb > 0.4 ||
        r.drugs > 0.4) {
      return RiskLevel.medium;
    }
    return RiskLevel.low;
  }

  String _buildSummary(SightengineResult r) {
    final flags = <String>[];
    if (r.nudityRaw > 0.4)     flags.add('Nudity (${_pct(r.nudityRaw)})');
    if (r.weapon > 0.4)        flags.add('Weapon (${_pct(r.weapon)})');
    if (r.offensiveProb > 0.4) flags.add('Offensive (${_pct(r.offensiveProb)})');
    if (r.drugs > 0.4)         flags.add('Drugs (${_pct(r.drugs)})');
    if (flags.isEmpty)         return 'No threats detected';
    return flags.join(' • ');
  }

  // ── Add to history ────────────────────────────────────────────────────────

  void _addToHistory(SightengineResult result) {
    final risk    = _computeRisk(result);
    final summary = _buildSummary(result);

    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id:            'media-${DateTime.now().millisecondsSinceEpoch}',
            type:          'image',
            title:         _fileName ?? 'Image',
            resultSummary: summary,
            date:          DateTime.now(),
            risk:          risk,
          ),
        );
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
                    'Upload images to detect nudity, weapons, drugs, or offensive content.',
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
              if (_loading && _statusMessage != null)
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
                          child: Text(_statusMessage!,
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
              if (_result != null) ...[
                _buildVerdictBanner(_result!),
                const SizedBox(height: 12),
                _buildNudityCard(context, _result!),
                const SizedBox(height: 12),
                _buildWeaponDrugsCard(context, _result!),
                const SizedBox(height: 12),
                _buildOffensiveCard(context, _result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Verdict banner ────────────────────────────────────────────────────────

  Widget _buildVerdictBanner(SightengineResult r) {
    final risk = _computeRisk(r);

    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    switch (risk) {
      case RiskLevel.high:
        bg      = Colors.red.shade50;
        fg      = Colors.red.shade800;
        icon    = Icons.gpp_bad;
        title   = 'High Risk Content Detected';
        subtitle = _buildSummary(r) + '. Parent has been notified.';
        break;
      case RiskLevel.medium:
        bg      = Colors.orange.shade50;
        fg      = Colors.orange.shade800;
        icon    = Icons.gpp_maybe;
        title   = 'Suspicious Content Found';
        subtitle = _buildSummary(r) + '. Review recommended.';
        break;
      case RiskLevel.low:
        bg      = Colors.green.shade50;
        fg      = Colors.green.shade800;
        icon    = Icons.verified_user;
        title   = 'Image Appears Safe';
        subtitle = 'No significant threats detected in this image.';
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

  // ── Nudity card ───────────────────────────────────────────────────────────

  Widget _buildNudityCard(BuildContext context, SightengineResult r) {
    return _buildCategoryCard(
      context: context,
      icon: Icons.no_adult_content,
      title: 'Nudity Detection',
      rows: [
        _ScoreRow('Explicit (Raw)',  r.nudityRaw,     _thresholdColor(r.nudityRaw)),
        _ScoreRow('Partial',         r.nudityPartial, _thresholdColor(r.nudityPartial)),
        _ScoreRow('Safe',            r.nuditySafe,    Colors.green),
      ],
    );
  }

  // ── Weapon & drugs card ───────────────────────────────────────────────────

  Widget _buildWeaponDrugsCard(BuildContext context, SightengineResult r) {
    return _buildCategoryCard(
      context: context,
      icon: Icons.warning_amber_outlined,
      title: 'Weapon & Substances',
      rows: [
        _ScoreRow('Weapon (overall)',  r.weapon,           _thresholdColor(r.weapon)),
        _ScoreRow('Firearm',           r.weaponFirearm,    _thresholdColor(r.weaponFirearm)),
        _ScoreRow('Knife',             r.weaponKnife,      _thresholdColor(r.weaponKnife)),
        _ScoreRow('Alcohol',           r.alcohol,          _thresholdColor(r.alcohol)),
        _ScoreRow('Drugs (overall)',   r.drugs,            _thresholdColor(r.drugs)),
        _ScoreRow('Recreational',      r.recreationalDrugs,_thresholdColor(r.recreationalDrugs)),
        _ScoreRow('Medical',           r.medicalDrugs,     Colors.grey),
      ],
    );
  }

  // ── Offensive card ────────────────────────────────────────────────────────

  Widget _buildOffensiveCard(BuildContext context, SightengineResult r) {
    return _buildCategoryCard(
      context: context,
      icon: Icons.block,
      title: 'Offensive Content',
      rows: [
        _ScoreRow('Overall',        r.offensiveProb,       _thresholdColor(r.offensiveProb)),
        _ScoreRow('Nazi',           r.offensiveNazi,       _thresholdColor(r.offensiveNazi)),
        _ScoreRow('Supremacist',    r.offensiveSupremacist,_thresholdColor(r.offensiveSupremacist)),
        _ScoreRow('Terrorist',      r.offensiveTerrorist,  _thresholdColor(r.offensiveTerrorist)),
        _ScoreRow('Middle finger',  r.offensiveMiddleFinger,_thresholdColor(r.offensiveMiddleFinger)),
      ],
    );
  }

  // ── Shared category card ──────────────────────────────────────────────────

  Widget _buildCategoryCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required List<_ScoreRow> rows,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            ...rows.map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(row.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          Text(_pct(row.value),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: row.color,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: row.value.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor:
                              AlwaysStoppedAnimation<Color>(row.color),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  Color _thresholdColor(double v) {
    if (v > 0.7) return Colors.red;
    if (v > 0.4) return Colors.orange;
    return Colors.green;
  }
}

// ── Sightengine result model ──────────────────────────────────────────────────

class SightengineResult {
  SightengineResult({
    required this.nudityRaw,
    required this.nuditySafe,
    required this.nudityPartial,
    required this.weapon,
    required this.weaponFirearm,
    required this.weaponKnife,
    required this.alcohol,
    required this.drugs,
    required this.medicalDrugs,
    required this.recreationalDrugs,
    required this.offensiveProb,
    required this.offensiveNazi,
    required this.offensiveConfederate,
    required this.offensiveSupremacist,
    required this.offensiveTerrorist,
    required this.offensiveMiddleFinger,
    required this.mediaUri,
  });

  final double nudityRaw;
  final double nuditySafe;
  final double nudityPartial;
  final double weapon;
  final double weaponFirearm;
  final double weaponKnife;
  final double alcohol;
  final double drugs;
  final double medicalDrugs;
  final double recreationalDrugs;
  final double offensiveProb;
  final double offensiveNazi;
  final double offensiveConfederate;
  final double offensiveSupremacist;
  final double offensiveTerrorist;
  final double offensiveMiddleFinger;
  final String mediaUri;

  factory SightengineResult.fromJson(Map<String, dynamic> json) {
    double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

    final nudity    = json['nudity']    as Map<String, dynamic>? ?? {};
    final offensive = json['offensive'] as Map<String, dynamic>? ?? {};

    return SightengineResult(
      nudityRaw:            _d(nudity['raw']),
      nuditySafe:           _d(nudity['safe']),
      nudityPartial:        _d(nudity['partial']),
      weapon:               _d(json['weapon']),
      weaponFirearm:        _d(json['weapon_firearm']),
      weaponKnife:          _d(json['weapon_knife']),
      alcohol:              _d(json['alcohol']),
      drugs:                _d(json['drugs']),
      medicalDrugs:         _d(json['medical_drugs']),
      recreationalDrugs:    _d(json['recreational_drugs']),
      offensiveProb:        _d(offensive['prob']),
      offensiveNazi:        _d(offensive['nazi']),
      offensiveConfederate: _d(offensive['confederate']),
      offensiveSupremacist: _d(offensive['supremacist']),
      offensiveTerrorist:   _d(offensive['terrorist']),
      offensiveMiddleFinger:_d(offensive['middle_finger']),
      mediaUri:             (json['media'] as Map<String, dynamic>?)?['uri']
                                as String? ?? '',
    );
  }
}

// ── Internal row model ────────────────────────────────────────────────────────

class _ScoreRow {
  const _ScoreRow(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color  color;
}