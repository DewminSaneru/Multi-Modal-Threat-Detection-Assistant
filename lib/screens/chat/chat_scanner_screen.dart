import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/detection_models.dart';
import '../../models/whatsapp_analysis.dart';
import '../../providers/scanner_provider.dart';
import '../../services/whatsapp_socket_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

const Map<String, String> _emojiMap = {
  'anger':         '😠',
  'fear':          '😨',
  'sadness':       '😢',
  'confusion':     '😕',
  'embarrassment': '😳',
  'caring':        '🤗',
  'love':          '❤️',
  'neutral':       '😐',
};

Color _emotionColor(String emotion) {
  switch (emotion.toLowerCase()) {
    case 'anger':         return const Color(0xFFEF5350);
    case 'fear':          return const Color(0xFF4DD0E1);
    case 'sadness':       return const Color(0xFF60A5FA);
    case 'confusion':     return const Color(0xFFfbbf24);
    case 'embarrassment': return const Color(0xFFf97316);
    case 'caring':        return const Color(0xFF3ED3A3);
    case 'love':          return const Color(0xFFec4899);
    default:              return Colors.grey;
  }
}

Color _windowRiskColor(double risk) {
  if (risk < 40) return const Color(0xFF3ED3A3);
  if (risk < 55) return const Color(0xFFFFA726);
  if (risk < 70) return const Color(0xFFFF7043);
  return const Color(0xFFEF5350);
}

String _windowRiskLabel(double risk) {
  if (risk < 40) return 'SAFE';
  if (risk < 55) return 'MILD';
  if (risk < 70) return 'MEDIUM';
  return 'HIGH';
}

Color _messageRiskColor(double risk) {
  if (risk < 5)  return const Color(0xFF3ED3A3);
  if (risk < 15) return const Color(0xFFFFA726);
  return const Color(0xFFEF5350);
}

Color _alertLevelColor(AlertLevel level) {
  switch (level) {
    case AlertLevel.mild:   return const Color(0xFFFFA726);
    case AlertLevel.medium: return const Color(0xFFFF7043);
    case AlertLevel.high:   return const Color(0xFFEF5350);
  }
}

/// Maps AlertLevel → RiskLevel for history/email
RiskLevel _alertLevelToRisk(AlertLevel level) {
  switch (level) {
    case AlertLevel.high:   return RiskLevel.high;
    case AlertLevel.medium: return RiskLevel.medium;
    case AlertLevel.mild:   return RiskLevel.medium; // mild still warrants medium email
  }
}

String _formatAlertTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ChatScannerScreen extends ConsumerStatefulWidget {
  const ChatScannerScreen({super.key});

  @override
  ConsumerState<ChatScannerScreen> createState() => _ChatScannerScreenState();
}

class _ChatScannerScreenState extends ConsumerState<ChatScannerScreen> {
  /// Tracks which alert timestamps have already been saved to history
  /// so we never send duplicate emails for the same alert.
  final Set<int> _savedAlertTimestamps = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(whatsAppSocketProvider);
      svc.connect(kWhatsAppServerUrl);

      // Listen for new risk alerts → save to history → backend sends email
      svc.addListener(_onSocketUpdate);
    });
  }

  @override
  void dispose() {
    // Safe: provider may already be disposed if screen is removed from tree
    try {
      ref.read(whatsAppSocketProvider).removeListener(_onSocketUpdate);
    } catch (_) {}
    super.dispose();
  }

  // ── Socket listener: fires whenever WhatsAppSocketService notifies ─────────

  void _onSocketUpdate() {
    if (!mounted) return;
    final svc = ref.read(whatsAppSocketProvider);

    for (final alert in svc.alerts) {
      final ts = alert.timestamp.millisecondsSinceEpoch;

      // Skip if we already processed this alert
      if (_savedAlertTimestamps.contains(ts)) continue;
      _savedAlertTimestamps.add(ts);

      final risk = _alertLevelToRisk(alert.level);

      // Save to scan history → backend reads risk level and emails parent
      ref.read(scanHistoryNotifierProvider.notifier).addEntry(
        ScanHistoryEntry(
          id:            'chat-$ts',
          type:          'chat',
          title:         'WhatsApp Risk Alert',
          resultSummary: '${alert.level.label} risk • '
                         '${_emojiMap[alert.dominantEmotion] ?? ''} '
                         '${alert.dominantEmotion} emotion • '
                         'score ${alert.windowRisk.toStringAsFixed(1)} • '
                         '${alert.messageCount} messages',
          date:          alert.timestamp,
          risk:          risk,  // high/medium → parent email sent by backend
        ),
      );
    }
  }

  // ── Unlink ────────────────────────────────────────────────────────────────

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
              // Clear saved timestamps so re-link starts fresh
              _savedAlertTimestamps.clear();
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc    = ref.watch(whatsAppSocketProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(svc),
      body: SafeArea(
        child: svc.isReady
            ? _buildDashboard(svc, isDark)
            : _buildConnectPhase(svc, isDark),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(WhatsAppSocketService svc) {
    final win = svc.windowData;
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('WhatsApp Risk Monitor',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, fontSize: 17)),
        ],
      ),
      actions: [
        if (win != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              label: Text(_windowRiskLabel(win.windowRisk),
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.bold)),
              backgroundColor:
                  _windowRiskColor(win.windowRisk).withOpacity(0.14),
              labelStyle: TextStyle(
                  color: _windowRiskColor(win.windowRisk)),
              side: BorderSide(
                  color:
                      _windowRiskColor(win.windowRisk).withOpacity(0.4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        if (svc.isReady)
          IconButton(
            icon: const Icon(Icons.link_off_rounded),
            tooltip: 'Unlink Device',
            color: Colors.grey,
            onPressed: () => _confirmUnlink(context),
          ),
      ],
    );
  }

  // ── Connection Phase ──────────────────────────────────────────────────────

  Widget _buildConnectPhase(WhatsAppSocketService svc, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'WhatsApp / Telegram Emotion Monitor',
          subtitle:
              'Real-time emotional risk analysis of chat conversations',
        ),
        const SizedBox(height: 16),

        // Server status banner
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  color:
                      svc.isConnected ? AppTheme.accent : Colors.grey,
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
                  color:
                      svc.isConnected ? AppTheme.accent : Colors.grey,
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
                          fontSize: 12,
                          color: const Color(0xFFEF5350))),
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
                  const CircularProgressIndicator(
                      color: AppTheme.accent),
                  const SizedBox(height: 14),
                  Text('Authenticated — starting up…',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey)),
                ] else ...[
                  const CircularProgressIndicator(
                      color: AppTheme.accent),
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
                ].asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.accent.withOpacity(0.15),
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
                                      fontSize: 12,
                                      color: Colors.grey)),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Dashboard Phase ───────────────────────────────────────────────────────

  Widget _buildDashboard(WhatsAppSocketService svc, bool isDark) {
    final win = svc.windowData;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'WhatsApp Emotion Monitor',
          subtitle:
              'Real-time emotional risk analysis of chat conversations',
        ),
        const SizedBox(height: 16),

        if (win != null) ...[
          Row(
            children: [
              Expanded(
                child: _statCard(
                  icon: Icons.monitor_heart_rounded,
                  label: 'Window Risk',
                  value: win.windowRisk.toStringAsFixed(1),
                  color: _windowRiskColor(win.windowRisk),
                  sub: _windowRiskLabel(win.windowRisk),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  icon: Icons.psychology_rounded,
                  label: 'Dominant Emotion',
                  value:
                      '${_emojiMap[win.dominantEmotion] ?? ''} ${win.dominantEmotion}',
                  color: _emotionColor(win.dominantEmotion),
                  sub: '${win.window.length} messages',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRiskGauge(win.windowRisk),
          const SizedBox(height: 12),
          _buildEmotionPieChart(win),
          const SizedBox(height: 12),
          _buildResultsCard(win),
          const SizedBox(height: 12),
        ] else ...[
          _buildEmptyState(),
          const SizedBox(height: 12),
        ],

        _buildAlertsSection(svc),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Stat card ─────────────────────────────────────────────────────────────

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required String sub,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color),
                overflow: TextOverflow.ellipsis),
            Text(sub,
                style: GoogleFonts.inter(
                    fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ── Risk gauge ────────────────────────────────────────────────────────────

  Widget _buildRiskGauge(double risk) {
    final color    = _windowRiskColor(risk);
    const maxRisk  = 100.0;
    final fraction = (risk / maxRisk).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.speed_rounded,
                      color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Window Risk Gauge',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Text(_windowRiskLabel(risk),
                      style: GoogleFonts.inter(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              builder: (_, v, __) => Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 18,
                      backgroundColor: color.withOpacity(0.1),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.grey)),
                      Text(
                        '${risk.toStringAsFixed(1)} / $maxRisk',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w600),
                      ),
                      Text('$maxRisk',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _riskLegendItem(
                    const Color(0xFF3ED3A3), 'SAFE <40'),
                _riskLegendItem(
                    const Color(0xFFFFA726), 'MILD <55'),
                _riskLegendItem(
                    const Color(0xFFFF7043), 'MED <70'),
                _riskLegendItem(
                    const Color(0xFFEF5350), 'HIGH ≥70'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskLegendItem(Color c, String label) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  GoogleFonts.inter(fontSize: 9, color: Colors.grey)),
        ],
      );

  // ── Emotion Pie Chart ─────────────────────────────────────────────────────

  Widget _buildEmotionPieChart(WindowData win) {
    final counts = <String, int>{};
    for (final m in win.window) {
      counts[m.emotion] = (counts[m.emotion] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final total   = counts.values.fold(0, (a, b) => a + b);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sections = entries.map((e) {
      final pct = e.value / total;
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: _emotionColor(e.key),
        radius: 56,
        title: pct >= 0.08
            ? '${(pct * 100).toStringAsFixed(0)}%'
            : '',
        titleStyle: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:
                        AppTheme.accentBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.donut_large_rounded,
                      color: AppTheme.accentBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Emotion Distribution',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text('Across current window',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 36,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(enabled: false),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: entries.map((e) {
                final pct   = e.value / total;
                final color = _emotionColor(e.key);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_emojiMap[e.key] ?? ''} ${e.key} '
                      '(${(pct * 100).toStringAsFixed(0)}%)',
                      style: GoogleFonts.inter(
                          fontSize: 10, color: Colors.grey),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Alerts section ────────────────────────────────────────────────────────

  Widget _buildAlertsSection(WhatsAppSocketService svc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5350).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.history_rounded,
                      color: Color(0xFFEF5350), size: 18),
                ),
                const SizedBox(width: 10),
                Text('Alert History',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                if (svc.alerts.isNotEmpty) ...[
                  Text('${svc.alerts.length}',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFEF5350))),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ref.read(whatsAppSocketProvider).clearAlerts();
                      _savedAlertTimestamps.clear();
                    },
                    style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                    child: Text('Clear',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey)),
                  ),
                ],
              ],
            ),

            if (svc.isInCooldown) ...[
              const SizedBox(height: 8),
              _buildCooldownBanner(svc.cooldownUntil),
            ],

            const SizedBox(height: 10),

            if (svc.alerts.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 36,
                          color: Colors.grey.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text('No alerts yet',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              ...svc.alerts.map(_buildAlertTile),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertTile(RiskAlert alert) {
    final color = _alertLevelColor(alert.level);
    // Check if this alert was emailed (it was saved to history → backend emailed)
    final wasEmailed = _savedAlertTimestamps
        .contains(alert.timestamp.millisecondsSinceEpoch);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3, height: 52,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(alert.level.label,
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ),
                    const SizedBox(width: 6),
                    // Email sent badge
                    if (wasEmailed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.email_outlined,
                                size: 11, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text('Parent notified',
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.grey)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    Text(_formatAlertTime(alert.timestamp),
                        style: GoogleFonts.inter(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _riskDetailChip(
                      Icons.monitor_heart_rounded,
                      'Window risk: ${alert.windowRisk.toStringAsFixed(1)}',
                      color,
                    ),
                    _riskDetailChip(
                      Icons.psychology_rounded,
                      '${_emojiMap[alert.dominantEmotion] ?? ''} ${alert.dominantEmotion}',
                      _emotionColor(alert.dominantEmotion),
                    ),
                    _riskDetailChip(
                      Icons.chat_bubble_outline_rounded,
                      '${alert.messageCount} msgs in window',
                      Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskDetailChip(IconData icon, String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style:
                  GoogleFonts.inter(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _buildCooldownBanner(DateTime until) {
    final h = until.hour.toString().padLeft(2, '0');
    final m = until.minute.toString().padLeft(2, '0');
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.accentBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppTheme.accentBlue.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined,
              size: 13, color: AppTheme.accentBlue),
          const SizedBox(width: 6),
          Text(
            'Alert cooldown active — resets at $h:$m',
            style: GoogleFonts.inter(
                fontSize: 11, color: AppTheme.accentBlue),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 36, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.analytics_outlined,
                size: 48,
                color: AppTheme.accent.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text('Waiting for live data',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              'Analysis results will appear once the backend processes messages',
              style:
                  GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Results card ──────────────────────────────────────────────────────────

  Widget _buildResultsCard(WindowData win) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color:
                        AppTheme.accentBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.message_rounded,
                      color: AppTheme.accentBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Message Analysis',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text('${win.window.length} messages',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 14),
            ...win.window.map(_buildMessageCard),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(AnalysisResult msg) {
    final rColor = _messageRiskColor(msg.messageRisk);
    final eColor = _emotionColor(msg.emotion);
    final emoji  = _emojiMap[msg.emotion] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Direction badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  msg.direction == 'sent' ? '↑ Sent' : '↓ Recv',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.accentBlue,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              // Emotion badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: eColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$emoji ${msg.emotion}',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: eColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              // Intensity badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(msg.intensity,
                    style: GoogleFonts.inter(
                        fontSize: 10, color: Colors.grey)),
              ),
              const Spacer(),
              // Risk badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: rColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: rColor.withOpacity(0.35)),
                ),
                child: Text(
                  'Risk ${msg.messageRisk.toStringAsFixed(1)}',
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: rColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Confidence bar
          Row(
            children: [
              Text('Confidence',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.grey)),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: msg.confidence,
                    minHeight: 5,
                    backgroundColor:
                        Colors.grey.withOpacity(0.1),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(eColor),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(msg.confidence * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(
                    fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
