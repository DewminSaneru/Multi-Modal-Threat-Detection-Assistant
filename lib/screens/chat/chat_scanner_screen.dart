import 'package:flutter/material.dart';

import '../../widgets/section_header.dart';
import '../../theme/app_theme.dart';

class ChatScannerScreen extends StatefulWidget {
  const ChatScannerScreen({super.key});

  @override
  State<ChatScannerScreen> createState() => _ChatScannerScreenState();
}

class _ChatScannerScreenState extends State<ChatScannerScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  Map<String, double>? _emotionStatus;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    setState(() => _loading = true);
    
    // Simulate processing delay
    await Future.delayed(const Duration(seconds: 1));
    
    // Generate dummy emotion status data
    setState(() {
      _emotionStatus = {
        'Joy': 0.75,
        'Sadness': 0.25,
        'Anger': 0.15,
        'Fear': 0.30,
        'Surprise': 0.45,
        'Disgust': 0.10,
        'Neutral': 0.50,
        'Anxiety': 0.35,
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Scanner')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const SectionHeader(
                title: 'Scan WhatsApp / Telegram chats',
                subtitle: 'Paste or upload chat text to analyze emotional tone',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _controller,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText: 'Paste exported chat text here...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _runScan,
                            icon: const Icon(Icons.science),
                            label:
                                Text(_loading ? 'Scanning...' : 'Run analyzers'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () {
                              _controller.text =
                                  'John: I am really excited about this project!\n'
                                  'Alice: I feel a bit anxious about this deal.\n'
                                  'Bob: This makes me happy and optimistic.';
                            },
                            child: const Text('Load demo chat'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_emotionStatus != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology, color: AppTheme.accent),
                            const SizedBox(width: 8),
                            Text(
                              'Emotion Status',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._emotionStatus!.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      '${(entry.value * 100).toStringAsFixed(0)}%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: entry.value,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _getEmotionColor(entry.key),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getEmotionColor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'joy':
      case 'surprise':
        return Colors.green;
      case 'sadness':
        return Colors.blue;
      case 'anger':
        return Colors.red;
      case 'fear':
      case 'anxiety':
        return Colors.orange;
      case 'disgust':
        return Colors.purple;
      case 'neutral':
        return Colors.grey;
      default:
        return AppTheme.accent;
    }
  }
}

