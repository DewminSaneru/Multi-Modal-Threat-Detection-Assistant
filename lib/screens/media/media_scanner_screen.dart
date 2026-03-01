import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/detection_models.dart';
import '../../providers/scanner_provider.dart';
import '../../widgets/section_header.dart';

class MediaScannerScreen extends ConsumerStatefulWidget {
  const MediaScannerScreen({super.key});

  @override
  ConsumerState<MediaScannerScreen> createState() => _MediaScannerScreenState();
}

class _MediaScannerScreenState extends ConsumerState<MediaScannerScreen> {
  bool _loading = false;
  String? _fileName;

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'jpeg', 'mp4', 'mov'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.name;
    setState(() {
      _loading = true;
      _fileName = path;
    });
    final detection = ref.read(mlServiceProvider).scanMedia(path);
    ref.read(mediaDetectionProvider.notifier).state = detection;
    setState(() => _loading = false);

    ref.read(scanHistoryNotifierProvider.notifier).addEntry(
          ScanHistoryEntry(
            id: 'media-${DateTime.now().millisecondsSinceEpoch}',
            type: 'media',
            title: _fileName ?? 'Media',
            resultSummary: detection.isUnsafe
                ? 'Unsafe • ${detection.category}'
                : 'Safe • ${(detection.confidence * 100).toStringAsFixed(0)}% confidence',
            date: DateTime.now(),
            risk: detection.isUnsafe ? RiskLevel.high : RiskLevel.low,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final detection = ref.watch(mediaDetectionProvider);

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
                    'Upload images or videos to flag violence, nudity, or hate symbols.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1. Upload media',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickMedia,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: Text(_loading ? 'Scanning...' : 'Select file'),
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 8),
                        Text('Selected: $_fileName'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (detection != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Results',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: Icon(
                            detection.isUnsafe
                                ? Icons.error_outline
                                : Icons.verified_user,
                            color:
                                detection.isUnsafe ? Colors.redAccent : Colors.green,
                          ),
                          title: Text(detection.isUnsafe ? 'Unsafe' : 'Safe'),
                          subtitle: Text(
                              'Category: ${detection.category} • Confidence ${(detection.confidence * 100).toStringAsFixed(0)}%'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

