import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../widgets/scan_result_card.dart';
import '../../widgets/section_header.dart';

/// Filter type for history list. null = All.
enum _HistoryFilter { all, chats, media, files, links }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;

  static const Map<_HistoryFilter, String> _filterLabels = {
    _HistoryFilter.all: 'All',
    _HistoryFilter.chats: 'Chats',
    _HistoryFilter.media: 'Media',
    _HistoryFilter.files: 'Files',
    _HistoryFilter.links: 'Links',
  };

  bool _matches(ScanHistoryEntry h) {
    switch (_filter) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.chats:
        return h.type == 'chat';
      case _HistoryFilter.media:
        return h.type == 'media';
      case _HistoryFilter.files:
        return h.type == 'file';
      case _HistoryFilter.links:
        return h.type == 'url';
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final filtered = history.where(_matches).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Results history')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan history',
                subtitle: 'Summary of file, URL, chat, and media scans',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _HistoryFilter.values.map((f) {
                  return FilterChip(
                    label: Text(_filterLabels[f]!),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _filter == _HistoryFilter.all
                              ? 'No scans yet'
                              : 'No ${_filterLabels[_filter]} scans',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _filter == _HistoryFilter.all
                              ? 'Run file, link, chat, or media scans to see results here.'
                              : 'Try another filter or run a scan.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade500,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (h) => ScanResultCard(
                    title: h.title.length > 80
                        ? '${h.title.substring(0, 80)}...'
                        : h.title,
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

