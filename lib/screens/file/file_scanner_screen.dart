import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/scanner_provider.dart';
import '../../widgets/section_header.dart';

class FileScannerScreen extends ConsumerStatefulWidget {
  const FileScannerScreen({super.key});

  @override
  ConsumerState<FileScannerScreen> createState() => _FileScannerScreenState();
}

class _FileScannerScreenState extends ConsumerState<FileScannerScreen> {
  bool _loading = false;
  String? _fileName;
  String? _fileType;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _loading = true;
      _fileName = file.name;
      _fileType = file.extension ?? 'unknown';
    });
    final detection =
        ref.read(mlServiceProvider).scanFile(file.name, _fileType ?? 'unknown');
    ref.read(fileDetectionProvider.notifier).state = detection;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final detection = ref.watch(fileDetectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('File Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan files for malware',
                subtitle:
                    'Upload PDFs, EXE, APK, ZIP, DOCX and more to detect threats.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1. Choose file',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickFile,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_loading ? 'Scanning...' : 'Select file'),
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 8),
                        Text('Selected: $_fileName ($_fileType)'),
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
                            detection.isMalicious
                                ? Icons.warning_amber
                                : Icons.verified_user,
                            color: detection.isMalicious
                                ? Colors.redAccent
                                : Colors.green,
                          ),
                          title: Text(
                              detection.isMalicious ? 'Malicious' : 'Clean'),
                          subtitle: Text(
                              'Threat probability ${(detection.threatProbability * 100).toStringAsFixed(0)}%'),
                          trailing: Chip(label: Text(detection.fileType)),
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

