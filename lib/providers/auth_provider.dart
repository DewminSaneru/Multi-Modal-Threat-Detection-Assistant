import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class AuthController extends ChangeNotifier {
  final _api = ApiService();

  // ── State ─────────────────────────────────────────────────────────────────

  bool isAuthenticated = false;
  bool isLoading = false;
  String? email;
  String? name;
  String? userId;
  String? token;
  String? parentEmail;
  String? errorMessage;

  // Called after login/signup succeeds to load history
  // We store this callback so scanner_provider can register it
  Future<void> Function()? _onAuthSuccess;

  void setOnAuthSuccess(Future<void> Function() callback) {
    _onAuthSuccess = callback;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    isLoading = v;
    notifyListeners();
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> data) async {
    token = data['token'] as String?;
    final user = data['user'] as Map<String, dynamic>? ?? {};
    userId      = user['id']          as String?;
    email       = user['email']       as String?;
    name        = user['name']        as String?;
    parentEmail = user['parentEmail'] as String?;
    isAuthenticated = true;
    errorMessage = null;
    isLoading = false;
    notifyListeners();

    // Load history from server after auth
    await _onAuthSuccess?.call();
  }

  void _setError(Object e) {
    errorMessage = e.toString().replaceFirst('Exception: ', '');
    isLoading = false;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<void> login(String userEmail, String password) async {
    _setLoading(true);
    try {
      final data = await _api.login(email: userEmail, password: password);
      await _applyAuthResponse(data);
    } catch (e) {
      _setError(e);
    }
  }

  // ── Signup ────────────────────────────────────────────────────────────────

  Future<void> signup(
    String userEmail,
    String password, {
    String? userName,
    required String userParentEmail,
  }) async {
    _setLoading(true);
    try {
      final data = await _api.signup(
        email:       userEmail,
        password:    password,
        name:        userName,
        parentEmail: userParentEmail,
      );
      await _applyAuthResponse(data);
    } catch (e) {
      _setError(e);
    }
  }

  // ── Forgot password ───────────────────────────────────────────────────────

  Future<void> forgotPassword(String userEmail) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  void logout() {
    isAuthenticated = false;
    token       = null;
    userId      = null;
    email       = null;
    name        = null;
    parentEmail = null;
    errorMessage = null;
    notifyListeners();
  }
}

final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController();
});