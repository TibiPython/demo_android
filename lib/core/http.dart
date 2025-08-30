// lib/core/http.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'env.dart';

/// Proveedor único de Dio para toda la app.
/// OJO: baseUrl viene de kBaseUrl (lib/core/env.dart)
final dioProvider = Provider<Dio>((ref) {
  final options = BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  );

  final dio = Dio(options);

  // (Opcional) logs basados en tus prints actuales
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (req, h) {
        // debugPrint('*** Request *** ${req.method} ${req.uri}');
        h.next(req);
      },
      onResponse: (res, h) {
        // debugPrint('*** Response *** ${res.statusCode} ${res.requestOptions.uri}');
        h.next(res);
      },
      onError: (e, h) {
        // debugPrint('*** Error *** ${e.requestOptions.uri} -> ${e.message}');
        h.next(e);
      },
    ),
  );

  return dio;
});
