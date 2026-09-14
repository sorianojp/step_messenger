import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String? token;
  void Function()? onUnauthorized;
  Map<String, String> get headers => {
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri uri(String path) {
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        Uri.parse(path).hasScheme) {
      throw const ApiException('Invalid API path.');
    }
    return Uri.parse('$baseUrl$path');
  }

  Future<Json> request(String method, String path, {Json? body}) async {
    final request = http.Request(method, uri(path))
      ..followRedirects = false
      ..headers.addAll({...headers, 'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    return _decode(await _send(request));
  }

  Future<Json> upload(
    String path,
    Map<String, String> fields,
    List<String> files, {
    String field = 'attachments[]',
  }) async {
    final request = http.MultipartRequest('POST', uri(path))
      ..followRedirects = false
      ..headers.addAll(headers)
      ..fields.addAll(fields);
    for (final file in files) {
      request.files.add(await http.MultipartFile.fromPath(field, file));
    }
    return _decode(await _send(request));
  }

  Future<Uint8List> download(String path) async {
    final request = http.Request('GET', uri(path))
      ..followRedirects = false
      ..headers.addAll(headers);
    final response = await _send(request);
    if (response.statusCode >= 300) _decode(response);
    return response.bodyBytes;
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const ApiException(
        'Unable to connect to Uhoo! Check your connection and try again.',
      );
    } on http.ClientException {
      throw const ApiException('Unable to reach Uhoo! Please try again.');
    }
  }

  Json _decode(http.Response response) {
    Json data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      /* A proxy may return an HTML error. */
    }
    if (response.statusCode == 401) {
      if (token != null) onUnauthorized?.call();
      throw const ApiException(
        'Your session expired. Please sign in again.',
        401,
      );
    }
    if (response.statusCode >= 300) {
      final errors = data['errors'];
      final validation = errors is Map && errors.isNotEmpty
          ? (errors.values.first as List).first.toString()
          : null;
      throw ApiException(
        validation ??
            (response.statusCode >= 500
                ? 'The server could not complete this request. Please try again.'
                : data['message'] as String? ??
                      'The request could not be completed.'),
        response.statusCode,
      );
    }
    if (data.isEmpty && response.statusCode != 204) {
      throw const ApiException(
        'This address did not return a valid Uhoo! response.',
      );
    }
    return data;
  }

  void close() => _client.close();
}
