import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/scanner_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dashboard_summary_card.dart';
import '../../widgets/scan_result_card.dart';
import '../../widgets/section_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount =
        screenWidth > 900 ? 4 : screenWidth > 600 ? 3 : 2;
    final childAspectRatio =
        screenWidth > 900 ? 1.5 : screenWidth > 600 ? 1.3 : 1.05;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider).logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Security posture',
                subtitle: 'Live overview of your multi-modal scans',
              ),
              const SizedBox(height: 16),
              GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: const [
                  DashboardSummaryCard(
                    label: 'Malicious links',
                    value: '18 flagged',
                    icon: Icons.link_off,
                    trend: '+3 today',
                  ),
                  DashboardSummaryCard(
                    label: 'Sensitive media',
                    value: '6 detected',
                    icon: Icons.perm_media,
                    trend: 'Stable',
                  ),
                  DashboardSummaryCard(
                    label: 'Emotion insights',
                    value: 'Balanced',
                    icon: Icons.mood,
                    trend: '↑ positive',
                  ),
                  DashboardSummaryCard(
                    label: 'Malware files',
                    value: '2 quarantined',
                    icon: Icons.shield_moon,
                    trend: '↓ -1',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _ThreatsChart()),
                  if (MediaQuery.of(context).size.width > 700)
                    const SizedBox(width: 12),
                  if (MediaQuery.of(context).size.width > 700)
                    const Expanded(child: _QuickActions()),
                ],
              ),
              if (MediaQuery.of(context).size.width <= 700) ...[
                const SizedBox(height: 12),
                const _QuickActions(),
              ],
              const SizedBox(height: 20),
              const SectionHeader(
                title: 'Recent scans',
                subtitle: 'History stored locally (mock)',
              ),
              const SizedBox(height: 12),
              ...history
                  .map((h) => ScanResultCard(
                        title: h.title,
                        subtitle:
                            '${h.type.toUpperCase()} • ${h.resultSummary} • ${h.date.toLocal()}'
                                .split('.')
                                .first,
                        risk: h.risk,
                      ))
                  ,
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreatsChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Threat signals',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: List.generate(
                    6,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (i + 2) * 2.5,
                          color: i.isEven ? AppTheme.accent : AppTheme.accentBlue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => GoRouter.of(context).go('/chat'),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Scan chats'),
                ),
                ElevatedButton.icon(
                  onPressed: () => GoRouter.of(context).go('/links'),
                  icon: const Icon(Icons.link),
                  label: const Text('Scan URLs'),
                ),
                ElevatedButton.icon(
                  onPressed: () => GoRouter.of(context).go('/media'),
                  icon: const Icon(Icons.perm_media_outlined),
                  label: const Text('Scan media'),
                ),
                ElevatedButton.icon(
                  onPressed: () => GoRouter.of(context).go('/files'),
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: const Text('Scan files'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

