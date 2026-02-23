import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FaceRecord {
  final int id;
  final String name;
  final double liquidLevelCm;

  FaceRecord({
    required this.id,
    required this.name,
    required this.liquidLevelCm,
  });

  factory FaceRecord.fromJson(Map<String, dynamic> json) {
    return FaceRecord(
      id: json['id'] ?? 0,
      name: json['name'] ?? '用户',
      liquidLevelCm: (json['liquidLevelCm'] ?? 10.0).toDouble(),
    );
  }
}

class StatusData {
  final int faceId;
  final String faceName;
  final double setLevelCm;
  final double currentLevelCm;
  final int faceCount;
  final String? faceImageUrl;

  StatusData({
    required this.faceId,
    required this.faceName,
    required this.setLevelCm,
    required this.currentLevelCm,
    required this.faceCount,
    this.faceImageUrl,
  });

  factory StatusData.fromJson(Map<String, dynamic> json) {
    return StatusData(
      faceId: json['faceId'] ?? -1,
      faceName: json['faceName'] ?? '',
      setLevelCm: (json['setLevelCm'] ?? 0).toDouble(),
      currentLevelCm: (json['currentLevelCm'] ?? 0).toDouble(),
      faceCount: json['faceCount'] ?? 0,
      faceImageUrl: json['faceImageUrl'],
    );
  }
}

class Esp32Service extends ChangeNotifier {
  String _baseUrl = 'http://192.168.4.1';
  bool _isLoading = false;
  String? _error;

  List<FaceRecord> _faces = [];
  StatusData? _status;

  String get baseUrl => _baseUrl;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<FaceRecord> get faces => _faces;
  StatusData? get status => _status;

  Esp32Service() {
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('esp32_base_url') ?? 'http://192.168.4.1';
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_base_url', _baseUrl);
    notifyListeners();
  }

  Future<void> _request(Future<void> Function() fn) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await fn();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchStatus() async {
    await _request(() async {
      final res = await http.get(Uri.parse('$_baseUrl/api/status')).timeout(
        const Duration(seconds: 5),
      );
      if (res.statusCode != 200) throw Exception('请求失败: ${res.statusCode}');
      _status = StatusData.fromJson(jsonDecode(res.body));
    });
  }

  Future<void> fetchFaces() async {
    await _request(() async {
      final res = await http.get(Uri.parse('$_baseUrl/api/faces')).timeout(
        const Duration(seconds: 5),
      );
      if (res.statusCode != 200) throw Exception('请求失败: ${res.statusCode}');
      final list = jsonDecode(res.body) as List;
      _faces = list.map((e) => FaceRecord.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<Map<String, dynamic>?> enrollNewUser() async {
    try {
      final res = await http.post(Uri.parse('$_baseUrl/api/enroll')).timeout(
        const Duration(seconds: 10),
      );
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body);
        throw Exception(body['error'] ?? '录入失败');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> confirmEnroll(int id, String name) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/enroll/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'name': name}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      await fetchFaces();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteFace(int id) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/face/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      await fetchFaces();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> setLiquidLevel(int faceId, double levelCm) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/level/set'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'faceId': faceId, 'levelCm': levelCm}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      await fetchFaces();
      await fetchStatus();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  String get captureUrl => '$_baseUrl/api/capture';
}
