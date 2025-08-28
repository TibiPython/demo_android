import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import 'client_model.dart';

final clientesServiceProvider = Provider<ClientesService>((ref) {
  final dio = ref.read(dioProvider);
  return ClientesService(dio);
});

class ClientesService {
  final Dio _dio;
  ClientesService(this._dio);

  Future<ClientesResp> listar({String? buscar, int page = 1, int pageSize = 20}) async {
    final resp = await _dio.get('/clientes', queryParameters: {
      if (buscar != null && buscar.trim().isNotEmpty) 'buscar': buscar.trim(),
      'page': page,
      'page_size': pageSize,
    });
    return ClientesResp.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Cliente> getById(int id) async {
    final resp = await _dio.get('/clientes/$id');
    return Cliente.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Cliente> crear({required String nombre, required String telefono}) async {
    final resp = await _dio.post('/clientes', data: {'nombre': nombre.trim(), 'telefono': telefono.trim()});
    return Cliente.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Cliente> actualizar({required int id, required String nombre, required String telefono}) async {
    final resp = await _dio.put('/clientes/$id', data: {'nombre': nombre.trim(), 'telefono': telefono.trim()});
    return Cliente.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> eliminar(int id) async {
    await _dio.delete('/clientes/$id');
  }
}
