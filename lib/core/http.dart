// lib/core/http.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'env.dart';

/// Proveedor único de Dio para toda la app.
/// Base URL: kBaseUrl (lib/core/env.dart)
final dioProvider = Provider<Dio>((ref) {
  final options = BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
    // Conservamos tu manejo actual de status (comportamiento por defecto de Dio):
    // en 4xx/5xx entra a onError.
  );

  final dio = Dio(options);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (req, h) {
        // No alteramos headers ni auth para no romper nada existente.
        h.next(req);
      },
      onResponse: (res, h) {
        h.next(res);
      },
      onError: (e, h) {
        // ✅ Si el backend envía {"detail": "..."} o una lista de errores,
        // copiamos ese texto a *message* y *error* del DioException.
        try {
          dynamic data = e.response?.data;

          // Si llegó como String JSON, intenta parsear.
          if (data is String) {
            final s = data.trim();
            if (s.isNotEmpty && (s.startsWith('{') || s.startsWith('['))) {
              try { data = json.decode(s); } catch (_) {}
            }
          }

          // detail como string: {"detail": "mensaje"}
          if (data is Map && data['detail'] != null && data['detail'] is! List) {
            final detail = data['detail']?.toString().trim();
            if (detail != null && detail.isNotEmpty) {
              h.next(
                DioException(
                  requestOptions: e.requestOptions,
                  response: e.response,
                  type: e.type,
                  message: detail,      // <- poblamos message
                  error: detail,        // <- y también error
                ),
              );
              return;
            }
          }

          // detail como lista (Pydantic): {"detail":[{"msg":"..."} , ...]}
          if (data is Map && data['detail'] is List && (data['detail'] as List).isNotEmpty) {
            final list = data['detail'] as List;
            String? msg;
            final first = list.first;
            if (first is Map && first['msg'] != null) {
              msg = first['msg'].toString();
            } else {
              msg = first.toString();
            }
            if (msg != null && msg.trim().isNotEmpty) {
              final m = msg.trim();
              h.next(
                DioException(
                  requestOptions: e.requestOptions,
                  response: e.response,
                  type: e.type,
                  message: m,           // <- poblamos message
                  error: m,             // <- y también error
                ),
              );
              return;
            }
          }
        } catch (_) {
          // Si algo falla al parsear, seguimos con el error original.
        }

        // Si no había "detail", mantenemos el comportamiento de siempre.
        h.next(e);
      },
    ),
  );

  return dio;
});
