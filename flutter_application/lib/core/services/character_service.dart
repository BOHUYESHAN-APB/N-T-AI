import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class CharacterModel {
  final String name;
  final String path; // Relative path like /static/live2d/mao_pro/mao_pro.model3.json

  CharacterModel({required this.name, required this.path});

  factory CharacterModel.fromJson(Map<String, dynamic> json) {
    return CharacterModel(
      name: json['name'] ?? 'Unknown',
      path: json['path'] ?? '',
    );
  }
}

class CharacterService {
  static const String _kBackendUrlKey = 'settings.backend.url';
  static const String _kDefaultBackendUrl = 'http://localhost:8000';

  Future<String> get _baseUrl async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBackendUrlKey) ?? _kDefaultBackendUrl;
  }

  Future<List<CharacterModel>> listModels() async {
    final baseUrl = await _baseUrl;
    try {
      final response = await http.get(Uri.parse('$baseUrl/v1/models/list'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final List list = data['models'];
        return list.map((e) => CharacterModel.fromJson(e)).toList();
      }
    } catch (e) {
      print('Error listing models: $e');
    }
    return [];
  }

  Future<bool> uploadModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true, // Needed for web/some platforms, but for mobile path is better if available
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final baseUrl = await _baseUrl;
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/v1/models/upload'));
      
      if (file.path != null) {
        // Mobile/Desktop with path
        request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      } else if (file.bytes != null) {
        // Web or no path access
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          file.bytes!, 
          filename: file.name
        ));
      } else {
        return false;
      }

      try {
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode == 200) {
          return true;
        } else {
          print('Upload failed: ${response.body}');
        }
      } catch (e) {
        print('Error uploading model: $e');
      }
    }
    return false;
  }

  Future<bool> deleteModel(String path) async {
    final baseUrl = await _baseUrl;
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/v1/models/delete').replace(queryParameters: {'path': path}),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        print('Delete failed: ${response.body}');
      }
    } catch (e) {
      print('Error deleting model: $e');
    }
    return false;
  }
}
