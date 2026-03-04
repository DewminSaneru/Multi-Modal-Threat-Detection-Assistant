import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../widgets/scan_result_card.dart';
import '../../widgets/section_header.dart';

enum _HistoryFilter { all, chats, media, files, links }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.all;
  bool _refreshing = false;

  static const Map<_HistoryFilter, String> _filterLabels = {
    _HistoryFilter.all:   'All',
    _HistoryFilter.chats: 'Chats',
    _HistoryFilter.media: 'Media',
    _HistoryFilter.files: 'Files',
    _HistoryFilter.links: 'Links',
  };

  @override
  void initState() {
    super.initState();
    // Refresh from server each time this screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(scanHistoryNotifierProvider.notifier).loadFromServer();
    if (mounted) setState(() => _refreshing = false);
  }

  bool _matches(ScanHistoryEntry h) {
    switch (_filter) {
      case _HistoryFilter.all:   return true;
      case _HistoryFilter.chats: return h.type == 'chat';
      case _HistoryFilter.media: return h.type == 'image'; 
      case _HistoryFilter.files: return h.type == 'file';
      case _HistoryFilter.links: return h.type == 'url';
    }
  }

  Future<void> _confirmDelete(BuildContext context, ScanHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove "${entry.title.length > 50 ? '${entry.title.substring(0, 50)}...' : entry.title}" from history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(scanHistoryNotifierProvider.notifier).removeEntry(entry.id);
    }
  }

  Color _riskColor(RiskLevel risk) {
    switch (risk) {
      case RiskLevel.high:   return Colors.red;
      case RiskLevel.medium: return Colors.orange;
      case RiskLevel.low:    return Colors.green;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'file':  return Icons.insert_drive_file_outlined;
      case 'url':   return Icons.link;
      case 'chat':  return Icons.chat_bubble_outline;
      case 'image': return Icons.image_outlined; 
      default:      return Icons.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    final history  = ref.watch(historyProvider);
    final filtered = history.where(_matches).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results history'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _refresh,
            ),
        ],
      ),
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

              // ── Filter chips ───────────────────────────────────────────────
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

              // ── Count badge ────────────────────────────────────────────────
              if (history.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              // ── Empty state ────────────────────────────────────────────────
              if (filtered.isEmpty && !_refreshing)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _filter == _HistoryFilter.all
                              ? 'No scans yet'
                              : 'No ${_filterLabels[_filter]} scans',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _filter == _HistoryFilter.all
                              ? 'Run file, link, chat, or media scans to see results here.'
                              : 'Try another filter or run a scan.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Loading shimmer ────────────────────────────────────────────
              if (_refreshing && filtered.isEmpty)
                ...List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              // ── History entries ────────────────────────────────────────────
              ...filtered.map((h) => _buildHistoryCard(context, h)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, ScanHistoryEntry h) {
    final riskColor = _riskColor(h.risk);
    final shortTitle = h.title.length > 80
        ? '${h.title.substring(0, 80)}...'
        : h.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: riskColor.withOpacity(0.12),
            child: Icon(_typeIcon(h.type), color: riskColor, size: 20),
          ),
          title: Text(
            shortTitle,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                h.resultSummary,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      h.type.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Risk badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      h.risk.name.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color: riskColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  // Date
                  Text(
                    _formatDate(h.date),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: Colors.grey[400],
            onPressed: () => _confirmDelete(context, h),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inHours < 1)    return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)     return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}