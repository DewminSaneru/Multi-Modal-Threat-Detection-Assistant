import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../providers/scanner_provider.dart';
import '../../models/detection_models.dart';

import '../../services/whatsapp_socket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

const String _apiUrl = 'http://143.198.213.108:8000/predict';

// ─── Models ───────────────────────────────────────────────────────────────────

class MediaScanResult {
  MediaScanResult({
    required this.filename,
    required this.predictedClass,
    required this.confidence,
    required this.safetyStatus,
    required this.safetyAction,
    required this.safetyMessage,
    required this.allScores,
    required this.timestamp,
    this.messageId,
    this.senderName,
  });

  final String filename;
  final String predictedClass;
  final double confidence;
  final String safetyStatus;
  final String safetyAction;
  final String safetyMessage;
  final Map<String, double> allScores;
  final DateTime timestamp;
  final String? messageId;
  final String? senderName;

  factory MediaScanResult.fromJson(
    Map<String, dynamic> json, {
    String? messageId,
    String? senderName,
    String? filename,
  }) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    final safety    = json['safety']     as Map<String, dynamic>? ?? {};
    final rawScores = json['all_scores'] as Map<String, dynamic>? ?? {};
    return MediaScanResult(
      filename:       filename ?? json['filename'] as String? ?? 'image.jpg',
      predictedClass: json['predicted_class'] as String? ?? 'unknown',
      confidence:     d(json['confidence']),
      safetyStatus:   safety['status']  as String? ?? 'REVIEW',
      safetyAction:   safety['action']  as String? ?? 'review',
      safetyMessage:  safety['message'] as String? ?? '',
      allScores:      rawScores.map((k, v) => MapEntry(k, d(v))),
      timestamp:      DateTime.now(),
      messageId:      messageId,
      senderName:     senderName,
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

class MediaScanNotifier extends ChangeNotifier {
  final List<MediaScanResult> _results    = [];
  final Set<String>           _scannedIds = {};

  List<MediaScanResult> get results => List.unmodifiable(_results);
  bool hasScanned(String id) => _scannedIds.contains(id);

  void add(MediaScanResult r) {
    if (r.messageId != null) _scannedIds.add(r.messageId!);
    _results.insert(0, r);
    if (_results.length > 50) _results.removeLast();
    notifyListeners();
  }

  void clear() {
    _results.clear();
    _scannedIds.clear();
    notifyListeners();
  }
}

final mediaScanNotifierProvider =
    ChangeNotifierProvider<MediaScanNotifier>((_) => MediaScanNotifier());

// ─── Screen ───────────────────────────────────────────────────────────────────

class MediaScannerScreen extends ConsumerStatefulWidget {
  const MediaScannerScreen({super.key});

  @override
  ConsumerState<MediaScannerScreen> createState() => _MediaScannerScreenState();
}

class _MediaScannerScreenState extends ConsumerState<MediaScannerScreen> {
  final Set<String> _scanning = {};
  String? _scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(whatsAppSocketProvider);
      svc.connect(kWhatsAppServerUrl);
      svc.onImageMessage(_onNewImageMessage);
    });
  }

  @override
  void dispose() {
    ref.read(whatsAppSocketProvider)
        .removeImageMessageCallback(_onNewImageMessage);
    super.dispose();
  }

  void _onNewImageMessage(WhatsAppImageMessage msg) {
    if (!mounted) return;
    _scanImageUrl(
      imageUrl:   msg.imageUrl,
      messageId:  msg.messageId,
      senderName: msg.senderName,
      filename:   'wa_${msg.messageId.hashCode}.jpg',
    );
  }

  // ── Unlink / logout ───────────────────────────────────────────────────────

  void _confirmUnlink(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink Device',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          'This will disconnect WhatsApp and show the QR code again. '
          'You can re-link at any time.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(whatsAppSocketProvider).resetSession();
              ref.read(mediaScanNotifierProvider.notifier).clear();
            },
            child: Text('Unlink',
                style: GoogleFonts.inter(
                    color: const Color(0xFFEF5350),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Scan ─────────────────────────────────────────────────────────────────

  Future<void> _scanImageUrl({
    required String imageUrl,
    required String messageId,
    String? senderName,
    String? filename,
  }) async {
    final notifier = ref.read(mediaScanNotifierProvider.notifier);
    if (notifier.hasScanned(messageId) || _scanning.contains(messageId)) return;

    setState(() {
      _scanning.add(messageId);
      _scanError = null;
    });

    try {
      final List<int> bytes;
      if (imageUrl.startsWith('data:')) {
        final comma = imageUrl.indexOf(',');
        bytes = base64Decode(imageUrl.substring(comma + 1));
      } else {
        final imgResp = await http
            .get(Uri.parse(imageUrl))
            .timeout(const Duration(seconds: 20));
        if (imgResp.statusCode != 200) {
          throw Exception('Failed to download image (${imgResp.statusCode})');
        }
        bytes = imgResp.bodyBytes;
      }

      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes, filename: filename ?? 'image.jpg',
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception('Scan API error (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      notifier.add(MediaScanResult.fromJson(
        decoded,
        messageId:  messageId,
        senderName: senderName,
        filename:   filename,
      ));
      final scanResult = MediaScanResult.fromJson(
      decoded,
      messageId:  messageId,
      senderName: senderName,
      filename:   filename,
    );
    notifier.add(scanResult);

    // ← ADD THIS BLOCK
    final risk = scanResult.safetyStatus == 'BLOCKED'
        ? RiskLevel.high
        : scanResult.safetyStatus == 'WARNING'
            ? RiskLevel.medium
            : RiskLevel.low;

    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
      ScanHistoryEntry(
        id:            'media-${DateTime.now().millisecondsSinceEpoch}',
        type:          'image',
        title:         filename ?? 'WhatsApp Image',
        resultSummary: '${scanResult.safetyStatus} • ${scanResult.predictedClass} '
                      '(${(scanResult.confidence * 100).toStringAsFixed(0)}%)',
        date:          DateTime.now(),
        risk:          risk,
      ),
    );
    } catch (e) {
      if (mounted) {
        setState(() => _scanError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _scanning.remove(messageId));
    }
  }

  // ── Verdict helper ────────────────────────────────────────────────────────

  _VerdictConfig _verdictConfig(String status) {
    switch (status) {
      case 'BLOCKED':
        return _VerdictConfig(
          bg: const Color(0xFFFFF0F0), fg: const Color(0xFFC0392B),
          border: const Color(0xFFE74C3C), icon: Icons.gpp_bad_rounded,
          badge: 'BLOCKED', badgeBg: const Color(0xFFE74C3C),
        );
      case 'WARNING':
        return _VerdictConfig(
          bg: const Color(0xFFFFF8EC), fg: const Color(0xFFB7570A),
          border: const Color(0xFFF39C12), icon: Icons.gpp_maybe_rounded,
          badge: 'WARNING', badgeBg: const Color(0xFFF39C12),
        );
      case 'REVIEW':
        return _VerdictConfig(
          bg: const Color(0xFFF0F4FF), fg: const Color(0xFF2C3E8C),
          border: const Color(0xFF3B5BDB), icon: Icons.manage_search_rounded,
          badge: 'REVIEW', badgeBg: const Color(0xFF3B5BDB),
        );
      default:
        return _VerdictConfig(
          bg: const Color(0xFFF0FFF4), fg: const Color(0xFF1A6B3A),
          border: const Color(0xFF27AE60), icon: Icons.verified_user_rounded,
          badge: 'SAFE', badgeBg: const Color(0xFF27AE60),
        );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc    = ref.watch(whatsAppSocketProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(svc),
      body: SafeArea(
        child: svc.isReady
            ? _buildDashboard(isDark)
            : _buildConnectPhase(svc, isDark),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(WhatsAppSocketService svc) {
    final results = ref.watch(mediaScanNotifierProvider).results;
    final blocked = results.where((r) => r.safetyStatus == 'BLOCKED').length;

    return AppBar(
      title: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.image_search_rounded,
                color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Media Scanner',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, fontSize: 17)),
        ],
      ),
      actions: [
        if (blocked > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              label: Text('$blocked BLOCKED',
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFEF5350).withOpacity(0.14),
              labelStyle: const TextStyle(color: Color(0xFFEF5350)),
              side: const BorderSide(color: Color(0xFFEF5350), width: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        if (_scanning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accent),
                ),
                const SizedBox(width: 5),
                Text('${_scanning.length} scanning',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.accent)),
              ],
            ),
          ),
        // ── Unlink button — only shown when WhatsApp is linked ─────────────
        if (svc.isReady)
          IconButton(
            icon: const Icon(Icons.link_off_rounded),
            tooltip: 'Unlink Device',
            color: Colors.grey,
            onPressed: () => _confirmUnlink(context),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Connect Phase ─────────────────────────────────────────────────────────

  Widget _buildConnectPhase(WhatsAppSocketService svc, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'WhatsApp Media Monitor',
          subtitle:
              'Link your WhatsApp to automatically scan all incoming images for inappropriate content',
        ),
        const SizedBox(height: 16),

        // Server status banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF161B22) : Colors.white)
                .withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: svc.isConnected
                  ? AppTheme.accent.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: svc.isConnected ? AppTheme.accent : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(kWhatsAppServerUrl,
                    style: GoogleFonts.sourceCodePro(
                        fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(
                svc.isConnected ? 'Connected' : 'Connecting…',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: svc.isConnected ? AppTheme.accent : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        if (svc.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFEF5350).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFEF5350), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(svc.error!,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: const Color(0xFFEF5350))),
                ),
                TextButton(
                  onPressed: () => svc.connect(kWhatsAppServerUrl),
                  child: Text('Retry',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // QR / status card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (svc.waStatus == 'qr' && svc.qrString != null) ...[
                  Text('Scan QR Code',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Use WhatsApp to link this device',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: svc.qrString!,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ] else if (svc.waStatus == 'authenticated') ...[
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 14),
                  Text('Authenticated — starting up…',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey)),
                ] else ...[
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 14),
                  Text('Waiting for QR code…',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey)),
                ],

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('How to connect',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                ...[
                  'Open WhatsApp on your phone',
                  'Go to Settings → Linked Devices',
                  'Tap "Link a Device"',
                  'Scan the QR code above',
                  'Incoming images will be auto-scanned',
                ].asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('${e.key + 1}',
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accent)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(e.value,
                                  style: GoogleFonts.inter(
                                      fontSize: 12, color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentBlue.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.accentBlue, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What gets scanned?',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.accentBlue)),
                    const SizedBox(height: 4),
                    Text(
                      'All images received in your WhatsApp chats are automatically forwarded to the AI content scanner. Results are displayed here in real-time.',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dashboard Phase ───────────────────────────────────────────────────────

  Widget _buildDashboard(bool isDark) {
    final results = ref.watch(mediaScanNotifierProvider).results;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'WhatsApp Media Monitor',
          subtitle: 'Incoming images are automatically scanned for content safety',
        ),
        const SizedBox(height: 16),

        _buildStatsRow(results),
        const SizedBox(height: 12),

        if (_scanning.isNotEmpty) ...[
          _buildScanningBanner(),
          const SizedBox(height: 12),
        ],

        if (_scanError != null) ...[
          _buildErrorBanner(_scanError!),
          const SizedBox(height: 12),
        ],

        if (results.isEmpty)
          _buildEmptyState()
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text('Scan Results',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      ref.read(mediaScanNotifierProvider.notifier).clear(),
                  style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4)),
                  child: Text('Clear all',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
          ),
          ...results.map(_buildResultCard),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow(List<MediaScanResult> results) {
    return Row(
      children: [
        Expanded(child: _miniStat(Icons.image_outlined, 'Scanned',
            '${results.length}', AppTheme.accent)),
        const SizedBox(width: 8),
        Expanded(child: _miniStat(Icons.gpp_bad_rounded, 'Blocked',
            '${results.where((r) => r.safetyStatus == 'BLOCKED').length}',
            const Color(0xFFEF5350))),
        const SizedBox(width: 8),
        Expanded(child: _miniStat(Icons.gpp_maybe_rounded, 'Warning',
            '${results.where((r) => r.safetyStatus == 'WARNING').length}',
            const Color(0xFFFFA726))),
        const SizedBox(width: 8),
        Expanded(child: _miniStat(Icons.verified_user_rounded, 'Safe',
            '${results.where((r) => r.safetyStatus == 'SAFE').length}',
            const Color(0xFF3ED3A3))),
      ],
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Text(label,
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      );

  Widget _buildScanningBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accentBlue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accentBlue.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accentBlue),
            ),
            const SizedBox(width: 10),
            Text(
              'Scanning ${_scanning.length} image${_scanning.length > 1 ? 's' : ''}…',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.accentBlue),
            ),
          ],
        ),
      );

  Widget _buildErrorBanner(String error) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEF5350).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF5350), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFFEF5350))),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
              onPressed: () => setState(() => _scanError = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );

  Widget _buildEmptyState() => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.image_search_rounded,
                  size: 52, color: AppTheme.accent.withOpacity(0.35)),
              const SizedBox(height: 14),
              Text('Waiting for images',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                'Images received in your WhatsApp chats will be automatically scanned and results shown here.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  // ── Result card ───────────────────────────────────────────────────────────

  Widget _buildResultCard(MediaScanResult r) {
    final cfg = _verdictConfig(r.safetyStatus);
    final h   = r.timestamp.hour.toString().padLeft(2, '0');
    final m   = r.timestamp.minute.toString().padLeft(2, '0');
    final s   = r.timestamp.second.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cfg.border.withOpacity(0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(cfg.icon, color: cfg.fg, size: 20),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: cfg.badgeBg,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(cfg.badge,
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: cfg.fg.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(r.predictedClass.toUpperCase(),
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cfg.fg)),
                ),
                const Spacer(),
                Text('$h:$m:$s',
                    style:
                        GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(r.safetyMessage,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cfg.fg)),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.senderName != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(r.senderName!,
                          style: GoogleFonts.inter(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Text('Confidence',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: r.confidence,
                          minHeight: 6,
                          backgroundColor: Colors.grey.withOpacity(0.12),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(cfg.badgeBg),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(r.confidence * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cfg.fg),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildScorePills(r),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScorePills(MediaScanResult r) {
    final sorted = r.allScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: sorted.map((e) {
        final isTop = e.key == r.predictedClass;
        final color = _scoreColor(e.key, e.value);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(isTop ? 0.15 : 0.07),
            borderRadius: BorderRadius.circular(20),
            border: isTop ? Border.all(color: color.withOpacity(0.5)) : null,
          ),
          child: Text(
            '${_classLabel(e.key)} ${(e.value * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.inter(
                fontSize: 10,
                color: isTop ? color : Colors.grey,
                fontWeight: isTop ? FontWeight.bold : FontWeight.normal),
          ),
        );
      }).toList(),
    );
  }

  Color _scoreColor(String className, double value) {
    if (['porn', 'hentai'].contains(className) && value > 0.3) {
      return const Color(0xFFEF5350);
    }
    if (className == 'sexy' && value > 0.4) return Colors.orange;
    if (className == 'neutral') return const Color(0xFF3ED3A3);
    if (value > 0.6) return const Color(0xFFEF5350);
    if (value > 0.3) return Colors.orange;
    return const Color(0xFF3ED3A3);
  }

  String _classLabel(String className) {
    const labels = {
      'drawings': '🎨 Drawings',
      'hentai':   '🔞 Hentai',
      'neutral':  '✅ Neutral',
      'porn':     '🚫 Porn',
      'sexy':     '⚠️ Sexy',
      'violence': '🩸 Violence',
    };
    return labels[className] ?? className.toUpperCase();
  }
}

// ─── Verdict config ───────────────────────────────────────────────────────────

class _VerdictConfig {
  const _VerdictConfig({
    required this.bg, required this.fg, required this.border,
    required this.icon, required this.badge, required this.badgeBg,
  });
  final Color    bg, fg, border, badgeBg;
  final IconData icon;
  final String   badge;
}