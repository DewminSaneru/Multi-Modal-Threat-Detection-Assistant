import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthController extends ChangeNotifier {
  bool isAuthenticated = false;
  String? email;

  Future<void> login(String userEmail, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    isAuthenticated = true;
    email = userEmail;
    notifyListeners();
  }

  Future<void> signup(String userEmail, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    isAuthenticated = true;
    email = userEmail;
    notifyListeners();
  }

  Future<void> forgotPassword(String userEmail) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  void logout() {
    isAuthenticated = false;
    email = null;
    notifyListeners();
  }
}

final authProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController();
});

