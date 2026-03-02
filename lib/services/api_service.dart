import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ── Base URL ───────────────────────────────────────────────────────────────
  // Replace YOUR_LOCAL_IP with your PC's IPv4 address from ipconfig
  // Example: 'http://192.168.1.5:3000'
  // After deploying to Render, replace with your Render URL instead.
  static const String baseUrl = 'http://localhost:3000';

  // ── Signup ─────────────────────────────────────────────────────────────────

  Future<AuthResult> signup({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              if (name != null && name.isNotEmpty) 'name': name,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return AuthResult.success(
          token: body['token'] as String,
          userId: body['user']['id'] as String,
          email: body['user']['email'] as String,
          name: body['user']['name'] as String? ?? '',
        );
      } else {
        return AuthResult.failure(
          body['error'] as String? ?? 'Signup failed. Please try again.',
        );
      }
    } catch (e) {
      return AuthResult.failure('Cannot reach server. Check your connection.');
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return AuthResult.success(
          token: body['token'] as String,
          userId: body['user']['id'] as String,
          email: body['user']['email'] as String,
          name: body['user']['name'] as String? ?? '',
        );
      } else {
        return AuthResult.failure(
          body['error'] as String? ?? 'Login failed. Please try again.',
        );
      }
    } catch (e) {
      return AuthResult.failure('Cannot reach server. Check your connection.');
    }
  }
}

// ── AuthResult model ──────────────────────────────────────────────────────────

class AuthResult {
  AuthResult._({
    required this.success,
    this.token,
    this.userId,
    this.email,
    this.name,
    this.errorMessage,
  });

  factory AuthResult.success({
    required String token,
    required String userId,
    required String email,
    required String name,
  }) {
    return AuthResult._(
      success: true,
      token: token,
      userId: userId,
      email: email,
      name: name,
    );
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(success: false, errorMessage: message);
  }

  final bool success;
  final String? token;
  final String? userId;
  final String? email;
  final String? name;
  final String? errorMessage;
}