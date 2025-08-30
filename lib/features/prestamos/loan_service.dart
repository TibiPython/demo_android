import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';

final prestamosApiProvider = Provider<PrestamosApi>((ref) {
  final dio = ref.read(dioProvider);
  return PrestamosApi(dio);
});
final prestamosServiceProvider = prestamosApiProvider;

class PrestamosApi {
  PrestamosApi(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> list({int page = 1, int pageSize = 20, String? codCli}) async {
    final resp = await _dio.get('/prestamos', queryParameters: {
      'page': page, 'page_size': pageSize, if (codCli != null && codCli.trim().isNotEmpty) 'cod_cli': codCli.trim(),
    });
    return Map<String, dynamic>.from(resp.data as Map);
  }

  Future<Map<String, dynamic>> getById(int id) async {
    final resp = await _dio.get('/prestamos/$id');
    return Map<String, dynamic>.from(resp.data as Map);
  }

  Future<Map<String, dynamic>> getResumenByPrestamoId(int id) async {
    try {
      final r = await _dio.get('/prestamo/$id/resumen');
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      final r2 = await _dio.get('/cuotas/prestamo/$id/resumen');
      return Map<String, dynamic>.from(r2.data as Map);
    }
  }

  Future<Map<String, dynamic>> create({
    required String codCli, required double monto, required String modalidad,
    required String fechaInicio, required int numCuotas, required double tasaInteres,
  }) async {
    final resp = await _dio.post('/prestamos', data: {
      'cod_cli': codCli.trim(), 'monto': monto, 'modalidad': modalidad,
      'fecha_inicio': fechaInicio, 'num_cuotas': numCuotas, 'tasa_interes': tasaInteres,
    });
    return Map<String, dynamic>.from(resp.data as Map);
  }

  Future<Map<String, dynamic>> listar({String? codCli, int page = 1, int pageSize = 20})
    => list(page: page, pageSize: pageSize, codCli: codCli);
  Future<Map<String, dynamic>> obtener(int id) => getById(id);
  Future<Map<String, dynamic>> obtenerResumen(int id) => getResumenByPrestamoId(id);
  Future<Map<String, dynamic>> crear({
    required String codCli, required double monto, required String modalidad,
    required String fechaInicio, required int numCuotas, required double tasaInteres,
  }) => create(codCli: codCli, monto: monto, modalidad: modalidad,
               fechaInicio: fechaInicio, numCuotas: numCuotas, tasaInteres: tasaInteres);
}
