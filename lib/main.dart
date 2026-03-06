import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_bootstrap.dart';
import 'providers/theme_provider.dart';
import 'routes/app_router.dart';
import 'screens/media/shared_image_scan_screen.dart';
import 'theme/app_theme.dart';

// Global navigator key to push routes from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const _channel = MethodChannel('com.threatapp/share');

void main() {
  runApp(const ProviderScope(child: ThreatDetectionApp()));
}

class ThreatDetectionApp extends ConsumerStatefulWidget {
  const ThreatDetectionApp({super.key});

  @override
  ConsumerState<ThreatDetectionApp> createState() =>
      _ThreatDetectionAppState();
}

class _ThreatDetectionAppState extends ConsumerState<ThreatDetectionApp> {
  @override
  void initState() {
    super.initState();
    _checkForSharedImage();
  }

  Future<void> _checkForSharedImage() async {
    // Small delay to let the app fully initialize first
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final path =
          await _channel.invokeMethod<String>('getSharedImagePath');
      if (path != null && path.isNotEmpty && mounted) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const SharedImageScanScreen(),
            fullscreenDialog: true,
          ),
        );
      }
    } catch (_) {
      // No shared image — normal app launch, do nothing
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final router    = ref.watch(appRouterProvider);

    return AppBootstrap(
      child: MaterialApp.router(
        title: 'Multi-Modal Threat Detection Assistant',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: themeMode,
        theme: AppTheme.light.copyWith(
          textTheme: GoogleFonts.spaceGroteskTextTheme(),
        ),
        darkTheme: AppTheme.dark.copyWith(
          textTheme: GoogleFonts.spaceGroteskTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme,
          ),
        ),
      ),
    );
  }
}