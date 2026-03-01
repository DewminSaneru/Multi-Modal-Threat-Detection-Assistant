// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// class AuthController extends ChangeNotifier {
//   bool isAuthenticated = false;
//   String? email;

//   Future<void> login(String userEmail, String password) async {
//     await Future<void>.delayed(const Duration(milliseconds: 500));
//     isAuthenticated = true;
//     email = userEmail;
//     notifyListeners();
//   }

//   Future<void> signup(String userEmail, String password) async {
//     await Future<void>.delayed(const Duration(milliseconds: 700));
//     isAuthenticated = true;
//     email = userEmail;
//     notifyListeners();
//   }

//   Future<void> forgotPassword(String userEmail) async {
//     await Future<void>.delayed(const Duration(milliseconds: 500));
//   }

//   void logout() {
//     isAuthenticated = false;
//     email = null;
//     notifyListeners();
//   }
// }

// final authProvider = ChangeNotifierProvider<AuthController>((ref) {
//   return AuthController();
// });

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class AuthController extends ChangeNotifier {
  final _api = ApiService();

  // ── State ──────────────────────────────────────────────────────────────────

  bool isAuthenticated = false;
  bool isLoading = false;
  String? email;
  String? name;
  String? userId;
  String? token;
  String? errorMessage;

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<void> login(String userEmail, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final result = await _api.login(email: userEmail, password: password);

    if (result.success) {
      isAuthenticated = true;
      email = result.email;
      name = result.name;
      userId = result.userId;
      token = result.token;
      errorMessage = null;
    } else {
      isAuthenticated = false;
      errorMessage = result.errorMessage;
    }

    isLoading = false;
    notifyListeners();
  }

  // ── Signup ─────────────────────────────────────────────────────────────────

  Future<void> signup(String userEmail, String password, {String? userName}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final result = await _api.signup(
      email: userEmail,
      password: password,
      name: userName,
    );

    if (result.success) {
      isAuthenticated = true;
      email = result.email;
      name = result.name;
      userId = result.userId;
      token = result.token;
      errorMessage = null;
    } else {
      isAuthenticated = false;
      errorMessage = result.errorMessage;
    }

    isLoading = false;
    notifyListeners();
  }

  // ── Forgot password ────────────────────────────────────────────────────────
  // Placeholder — wire up a backend reset email endpoint when needed

  Future<void> forgotPassword(String userEmail) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  void logout() {
    isAuthenticated = false;
    email = null;
    name = null;
    userId = null;
    token = null;
    errorMessage = null;
    notifyListeners();
  }

  // ── Clear error ────────────────────────────────────────────────────────────

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }
}

final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController();
});