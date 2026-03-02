import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'providers/scanner_provider.dart';

class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  void initState() {
    super.initState();
    // Register the callback so AuthController can trigger history loading
    // without importing scanner_provider (avoids circular dependency).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider).setOnAuthSuccess(() async {
        await ref
            .read(scanHistoryNotifierProvider.notifier)
            .loadFromServer();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}