import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String kBaseUrl = 'http://127.0.0.1:8000'; // USB + adb reverse

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));
  dio.interceptors.add(LogInterceptor(
    request: true, requestBody: true,
    responseBody: true, error: true,
  ));
  return dio;
});
