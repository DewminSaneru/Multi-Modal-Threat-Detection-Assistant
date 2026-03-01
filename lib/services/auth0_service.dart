import 'dart:convert';

import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:http/http.dart' as http;

/// Central service that wraps the Auth0 Flutter SDK.
///
/// Usage:
///   final service = Auth0Service();
///   await service.loginWithEmail(email, password);
///   await service.loginWithGoogle();
///   await service.signup(email, password, name);
///   await service.logout();
class Auth0Service {
  Auth0Service()
      : _auth0 = Auth0(
          'dev-o6teqtdbx01o4ofe.us.auth0.com',
          'pHMGMjIay4P5RCDXJoiB0GAg6QjiP5Ve',
        );

  final Auth0 _auth0;

  // ── Credentials cache ─────────────────────────────────────────────────────

  Credentials? _credentials;

  UserProfile? get currentUser => _credentials?.user;
  String? get accessToken => _credentials?.accessToken;
  bool get isAuthenticated => _credentials != null;

  // ── Email / Password Login ────────────────────────────────────────────────

  /// Signs in with email + password using Auth0's Resource Owner Password flow.
  /// Requires the "Password" grant to be enabled in your Auth0 tenant
  /// (Auth0 Dashboard → Applications → APIs → Default → Settings → Allow Offline Access
  ///  and Advanced → Grant Types → Password).
  Future<UserProfile> loginWithEmail(String email, String password) async {
    try {
      _credentials = await _auth0.api.login(
        usernameOrEmail: email,
        password: password,
        connectionOrRealm: 'Username-Password-Authentication',
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );
      return _credentials!.user;
    } on ApiException catch (e) {
      throw _mapApiException(e);
    }
  }

  // ── Google Social Login ───────────────────────────────────────────────────

  /// Opens the Auth0 Universal Login page pre-selected to Google.
  /// Auth0 handles the Google OAuth flow; user details are saved in Auth0.
  Future<UserProfile> loginWithGoogle() async {
    try {
      _credentials = await _auth0.webAuthentication(scheme: 'demo').login(
        parameters: {'connection': 'google-oauth2'},
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );
      return _credentials!.user;
    } on WebAuthenticationException catch (e) {
      throw _mapWebException(e);
    }
  }

  // ── Universal Login (fallback / forgot password flow) ────────────────────

  Future<UserProfile> loginWithUniversalLogin() async {
    try {
      _credentials = await _auth0.webAuthentication(scheme: 'demo').login(
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );
      return _credentials!.user;
    } on WebAuthenticationException catch (e) {
      throw _mapWebException(e);
    }
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────

  /// Creates a new user in Auth0's database and returns their profile.
  /// After sign-up Auth0 requires an explicit login to get tokens,
  /// so we immediately log in after creation.
  Future<UserProfile> signup(
    String email,
    String password, {
    String? name,
  }) async {
    try {
      // 1. Create the account in Auth0 DB
      final newUser = await _auth0.api.signup(
        email: email,
        password: password,
        connection: 'Username-Password-Authentication',
        userMetadata: name != null ? {'name': name} : {},
      );

      // 2. Immediately authenticate to retrieve tokens
      _credentials = await _auth0.api.login(
        usernameOrEmail: email,
        password: password,
        connectionOrRealm: 'Username-Password-Authentication',
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );

      return _credentials!.user;
    } on ApiException catch (e) {
      throw _mapApiException(e);
    }
  }

  // ── Password Reset ────────────────────────────────────────────────────────

  /// Sends a password reset email via Auth0.
  Future<void> sendPasswordResetEmail(String email) async {
    final uri = Uri.parse(
        'https://dev-o6teqtdbx01o4ofe.us.auth0.com/dbconnections/change_password');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': 'pHMGMjIay4P5RCDXJoiB0GAg6QjiP5Ve',
        'email': email,
        'connection': 'Username-Password-Authentication',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Password reset failed (status ${response.statusCode})');
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _auth0.webAuthentication(scheme: 'demo').logout();
    } catch (_) {
      // Ignore logout errors — clear local state regardless
    } finally {
      _credentials = null;
    }
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  /// Silently refreshes the access token using the stored refresh token.
  Future<bool> refreshTokenIfNeeded() async {
    if (_credentials == null) return false;
    try {
      _credentials = await _auth0.api.renewCredentials(
        refreshToken: _credentials!.refreshToken ?? '',
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );
      return true;
    } catch (_) {
      _credentials = null;
      return false;
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────────

  String _mapApiException(ApiException e) {
    switch (e.code) {
      case 'invalid_grant':
      case 'access_denied':
        return 'Incorrect email or password.';
      case 'user_exists':
      case 'username_exists':
        return 'An account with this email already exists.';
      case 'password_strength_error':
        return 'Password is too weak. Please use a stronger password.';
      case 'too_many_attempts':
        return 'Too many login attempts. Please try again later.';
      case 'blocked_user':
        return 'This account has been blocked. Contact support.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  String _mapWebException(WebAuthenticationException e) {
    if (e.code == 'a0.authentication_manager.invalid_token') {
      return 'Sign-in was cancelled.';
    }
    return e.message ?? 'Sign-in failed. Please try again.';
  }
}