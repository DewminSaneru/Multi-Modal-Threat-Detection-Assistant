import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/detection_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scan_result_card.dart';
import '../../widgets/section_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final auth    = ref.watch(authProvider);
    final limited = history.take(6).toList();

    final high   = history.where((h) => h.risk == RiskLevel.high).length;
    final medium = history.where((h) => h.risk == RiskLevel.medium).length;
    final safe   = history.where((h) => h.risk == RiskLevel.low).length;
    final total  = history.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context, ref, auth),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [

            // ── Greeting banner ─────────────────────────────────────────────
            _GreetingBanner(name: auth.name ?? 'User'),
            const SizedBox(height: 20),

            // ── Protection status ring ───────────────────────────────────────
            _ProtectionStatusCard(
              total: total,
              high: high,
              medium: medium,
              safe: safe,
            ),
            const SizedBox(height: 16),

            // ── Scan category tiles ──────────────────────────────────────────
            const _ScanCategorySection(),
            const SizedBox(height: 16),

            // ── Threat breakdown row ─────────────────────────────────────────
            _ThreatBreakdownRow(high: high, medium: medium, safe: safe),
            const SizedBox(height: 16),

            // ── Tips carousel ────────────────────────────────────────────────
            const _SafetyTipsCard(),
            const SizedBox(height: 20),

            // ── Recent scans ─────────────────────────────────────────────────
            const SectionHeader(
              title: 'Recent Scans',
              subtitle: 'Last 6 scanned items across all categories',
            ),
            const SizedBox(height: 12),

            if (limited.isEmpty)
              _EmptyHistoryState()
            else
              ...limited.map(
                (h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ScanResultCard(
                    title: h.title,
                    subtitle:
                        '${h.type.toUpperCase()} • ${h.resultSummary} • '
                        '${h.date.toLocal()}'.split('.').first,
                    risk: h.risk,
                  ),
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, WidgetRef ref, dynamic auth) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.security_rounded,
                color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text('ThreatGuard',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Logout',
          onPressed: () {
            ref.read(authProvider).logout();
            context.go('/login');
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Greeting Banner ─────────────────────────────────────────────────────────

class _GreetingBanner extends StatelessWidget {
  const _GreetingBanner({required this.name});
  final String name;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2744), const Color(0xFF0F1A30)]
              : [const Color(0xFF2563EB).withOpacity(0.08),
                 const Color(0xFF7C3AED).withOpacity(0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.accent.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_greeting,',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(name,
                    style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3ED3A3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('All systems active & monitoring',
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shield_rounded,
                color: AppTheme.accent, size: 30),
          ),
        ],
      ),
    );
  }
}

// ─── Protection Status Card ───────────────────────────────────────────────────

class _ProtectionStatusCard extends StatelessWidget {
  const _ProtectionStatusCard({
    required this.total,
    required this.high,
    required this.medium,
    required this.safe,
  });

  final int total, high, medium, safe;

  String get _statusLabel {
    if (high > 0) return 'Threats Detected';
    if (medium > 0) return 'Caution Advised';
    if (total == 0) return 'Ready to Scan';
    return 'All Clear';
  }

  Color get _statusColor {
    if (high > 0) return const Color(0xFFEF5350);
    if (medium > 0) return const Color(0xFFFFA726);
    return const Color(0xFF3ED3A3);
  }

  IconData get _statusIcon {
    if (high > 0) return Icons.gpp_bad_rounded;
    if (medium > 0) return Icons.gpp_maybe_rounded;
    return Icons.verified_user_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = _statusColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Protection Status',
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
                        Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon, color: color, size: 13),
                      const SizedBox(width: 5),
                      Text(_statusLabel,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Scan type progress bars ──────────────────────────────────
            _ScanTypeMeter(
              label: 'Chat Monitor',
              icon: Icons.chat_bubble_rounded,
              color: const Color(0xFF60A5FA),
              statusText: 'WhatsApp connected',
              active: true,
            ),
            const SizedBox(height: 10),
            _ScanTypeMeter(
              label: 'Media Scanner',
              icon: Icons.image_search_rounded,
              color: const Color(0xFFA78BFA),
              statusText: 'Auto-scan enabled',
              active: true,
            ),
            const SizedBox(height: 10),
            _ScanTypeMeter(
              label: 'Link Inspector',
              icon: Icons.link_rounded,
              color: const Color(0xFF34D399),
              statusText: 'URL scanning ready',
              active: true,
            ),
            const SizedBox(height: 10),
            _ScanTypeMeter(
              label: 'File Analyser',
              icon: Icons.insert_drive_file_rounded,
              color: const Color(0xFFFBBF24),
              statusText: 'ML powered',
              active: true,
            ),

            if (total > 0) ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text('Lifetime scan summary',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SummaryPill('$total', 'Total', Colors.grey),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      '$safe', 'Safe', const Color(0xFF3ED3A3)),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      '$medium', 'Caution', const Color(0xFFFFA726)),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      '$high', 'Threats', const Color(0xFFEF5350)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScanTypeMeter extends StatelessWidget {
  const _ScanTypeMeter({
    required this.label,
    required this.icon,
    required this.color,
    required this.statusText,
    required this.active,
  });

  final String label, statusText;
  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  Text(statusText,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: active ? 1.0 : 0.0,
                  minHeight: 5,
                  backgroundColor: color.withOpacity(0.1),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF3ED3A3)
                : Colors.grey[400],
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill(this.value, this.label, this.color);
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ─── Scan Category Section ────────────────────────────────────────────────────

class _ScanCategorySection extends StatelessWidget {
  const _ScanCategorySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scan Tools',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: const [
            _ScanTile(
              route: '/chat',
              label: 'Chat Monitor',
              subtitle: 'Emotion & risk',
              icon: Icons.chat_bubble_rounded,
              color: Color(0xFF60A5FA),
            ),
            _ScanTile(
              route: '/media',
              label: 'Media Scan',
              subtitle: 'Image safety',
              icon: Icons.image_search_rounded,
              color: Color(0xFFA78BFA),
            ),
            _ScanTile(
              route: '/links',
              label: 'Link Check',
              subtitle: 'URL threats',
              icon: Icons.link_rounded,
              color: Color(0xFF34D399),
            ),
            _ScanTile(
              route: '/files',
              label: 'File Scan',
              subtitle: 'Malware detect',
              icon: Icons.insert_drive_file_rounded,
              color: Color(0xFFFBBF24),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({
    required this.route,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String route, label, subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => GoRouter.of(context).go(route),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 10, color: Colors.grey),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 11, color: color.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Threat Breakdown Row ─────────────────────────────────────────────────────

class _ThreatBreakdownRow extends StatelessWidget {
  const _ThreatBreakdownRow({
    required this.high,
    required this.medium,
    required this.safe,
  });

  final int high, medium, safe;

  @override
  Widget build(BuildContext context) {
    final total = (high + medium + safe).clamp(1, 9999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Threat Breakdown',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Stacked bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        if (high > 0)
                          Flexible(
                            flex: high,
                            child: Container(
                              color: const Color(0xFFEF5350),
                            ),
                          ),
                        if (medium > 0)
                          Flexible(
                            flex: medium,
                            child: Container(
                              color: const Color(0xFFFFA726),
                            ),
                          ),
                        if (safe > 0)
                          Flexible(
                            flex: safe,
                            child: Container(
                              color: const Color(0xFF3ED3A3),
                            ),
                          ),
                        if (high == 0 && medium == 0 && safe == 0)
                          Expanded(
                            child: Container(
                              color: Colors.grey[200],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _BreakdownLegend(
                      color: const Color(0xFFEF5350),
                      label: 'High Risk',
                      count: high,
                      pct: high * 100 ~/ total,
                    ),
                    _BreakdownLegend(
                      color: const Color(0xFFFFA726),
                      label: 'Medium',
                      count: medium,
                      pct: medium * 100 ~/ total,
                    ),
                    _BreakdownLegend(
                      color: const Color(0xFF3ED3A3),
                      label: 'Safe',
                      count: safe,
                      pct: safe * 100 ~/ total,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownLegend extends StatelessWidget {
  const _BreakdownLegend({
    required this.color,
    required this.label,
    required this.count,
    required this.pct,
  });

  final Color color;
  final String label;
  final int count, pct;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 9, height: 9,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$count',
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text('$pct%',
              style: GoogleFonts.inter(
                  fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ─── Safety Tips Card ─────────────────────────────────────────────────────────

class _SafetyTipsCard extends StatefulWidget {
  const _SafetyTipsCard();

  @override
  State<_SafetyTipsCard> createState() => _SafetyTipsCardState();
}

class _SafetyTipsCardState extends State<_SafetyTipsCard> {
  int _currentTip = 0;

  static const _tips = [
    _Tip(
      icon: Icons.link_off_rounded,
      color: Color(0xFFEF5350),
      title: 'Suspicious Links',
      body:
          'Never tap shortened URLs from unknown senders. Always verify the domain before entering credentials.',
    ),
    _Tip(
      icon: Icons.image_not_supported_rounded,
      color: Color(0xFFA78BFA),
      title: 'Media Threats',
      body:
          'Malicious images can carry hidden payloads. ThreatGuard scans every WhatsApp image automatically.',
    ),
    _Tip(
      icon: Icons.psychology_rounded,
      color: Color(0xFF60A5FA),
      title: 'Emotional Manipulation',
      body:
          'Cyberbullies exploit strong emotions. Our emotion AI flags high-risk conversations in real time.',
    ),
    _Tip(
      icon: Icons.insert_drive_file_rounded,
      color: Color(0xFFFBBF24),
      title: 'File Safety',
      body:
          'Avoid opening files from strangers. VirusTotal-powered scanning checks against 70+ engines.',
    ),
    _Tip(
      icon: Icons.lock_rounded,
      color: Color(0xFF34D399),
      title: 'Stay Protected',
      body:
          'Keep your parent email updated so ThreatGuard can send instant alerts when risks are detected.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tip = _tips[_currentTip];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Safety Tips',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Text('${_currentTip + 1} / ${_tips.length}',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(
                () => _currentTip = (_currentTip + 1) % _tips.length),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: tip.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tip.icon,
                        color: tip.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tip.title,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: tip.color)),
                        const SizedBox(height: 5),
                        Text(tip.body,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey[600],
                                height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: tip.color.withOpacity(0.5)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_tips.length, (i) {
            final active = i == _currentTip;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? tip.color
                    : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Tip {
  const _Tip({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title, body;
}

// ─── Empty History State ──────────────────────────────────────────────────────

class _EmptyHistoryState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 36, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.history_rounded,
                size: 48,
                color: AppTheme.accent.withOpacity(0.35)),
            const SizedBox(height: 12),
            Text('No scans yet',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Run your first scan using any of the tools above. '
              'Results will appear here.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}