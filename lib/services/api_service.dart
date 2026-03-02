import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:3000';

  // ── Signup ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String parentEmail,
    String? name,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email':       email,
            'password':    password,
            'parentEmail': parentEmail,
            if (name != null && name.isNotEmpty) 'name': name,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) return data;
    throw Exception(data['error'] ?? 'Signup failed');
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error'] ?? 'Login failed');
  }

  // ── History ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> getHistory(String token) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/history'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception(data['error'] ?? 'Failed to fetch history');
  }

  Future<Map<String, dynamic>> saveScanHistory({
    required String token,
    required String type,
    required String title,
    required String resultSummary,
    required String risk,
    Map<String, dynamic>? details,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/history'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'type':          type,
            'title':         title,
            'resultSummary': resultSummary,
            'risk':          risk,
            'details':       details ?? {},
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) return data;
    throw Exception(data['error'] ?? 'Failed to save history');
  }

  Future<void> deleteHistory(String token, String id) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/history/$id'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Failed to delete history entry');
    }
  }
}