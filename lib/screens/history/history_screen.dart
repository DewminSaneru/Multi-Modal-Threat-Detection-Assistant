import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/scanner_provider.dart';
import '../../widgets/scan_result_card.dart';
import '../../widgets/section_header.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Results history')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Stored scans',
                subtitle: 'Filter by type, date, or risk level (UI only)',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('Chats'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('Media'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('Files'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...history.map(
                (h) => ScanResultCard(
                  title: h.title,
                  subtitle:
                      '${h.type.toUpperCase()} • ${h.resultSummary} • ${h.date.toLocal()}'
                          .split('.')
                          .first,
                  risk: h.risk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

