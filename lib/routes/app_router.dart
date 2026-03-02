import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/chat/chat_scanner_screen.dart';
import '../screens/file/file_scanner_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/links/links_scanner_screen.dart';
import '../screens/media/media_scanner_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/profile/profile_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  final notifier = ref.read(authProvider.notifier);

  return GoRouter(
    initialLocation: auth.isAuthenticated ? '/home' : '/login',
    refreshListenable: notifier,
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) => const ChatScannerScreen(),
          ),
          GoRoute(
            path: '/media',
            builder: (context, state) => const MediaScannerScreen(),
          ),
          GoRoute(
            path: '/files',
            builder: (context, state) => const FileScannerScreen(),
          ),
          GoRoute(
            path: '/links',
            builder: (context, state) => const LinksScannerScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final loggedIn = ref.read(authProvider).isAuthenticated;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot';

      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/home';
      return null;
    },
  );
});

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  int _indexForLocation(String location) {
    switch (location) {
      case '/home':
        return 0;
      case '/chat':
        return 1;
      case '/media':
        return 2;
      case '/files':
        return 3;
      case '/links':
        return 4;
      case '/history':
        return 5;
      case '/settings':
        return 6;
      default:
        return 0;
    }
  }

  String _locationForIndex(int index) {
    switch (index) {
      case 0:
        return '/home';
      case 1:
        return '/chat';
      case 2:
        return '/media';
      case 3:
        return '/files';
      case 4:
        return '/links';
      case 5:
        return '/history';
      case 6:
        return '/settings';
      default:
        return '/home';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) =>
            GoRouter.of(context).go(_locationForIndex(index)),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.perm_media), label: 'Media'),
          NavigationDestination(icon: Icon(Icons.insert_drive_file), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.link), label: 'Links'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

