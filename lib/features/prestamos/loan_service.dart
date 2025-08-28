import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';

/// API provider (igual que en Clientes: inyectamos Dio desde dioProvider)
final prestamosApiProvider = Provider<PrestamosApi>((ref) {
  final dio = ref.read(dioProvider);
  return PrestamosApi(dio);
});

/// Alias por compatibilidad con otras pantallas que leen `prestamosServiceProvider`
final prestamosServiceProvider = prestamosApiProvider;

class PrestamosApi {
  PrestamosApi(this._dio);
  final Dio _dio;

  /// Listado con paginación y filtro opcional por código de cliente
  Future<Map<String, dynamic>> list({
    int page = 1,
    int pageSize = 20,
    String? codCli,
  }) async {
    final resp = await _dio.get(
      '/prestamos',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (codCli != null && codCli.trim().isNotEmpty) 'cod_cli': codCli.trim(),
      },
    );
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Obtener por ID
  Future<Map<String, dynamic>> getById(int id) async {
    final resp = await _dio.get('/prestamos/$id');
    return Map<String, dynamic>.from(resp.data as Map);
  }

  /// Crear préstamo (nombres de campos EXACTOS que espera el backend)
  Future<Map<String, dynamic>> create({
    required String codCli,          // ej: '006'
    required double monto,           // ej: 1000000
    required String modalidad,       // 'MENSUAL' | 'QUINCENAL' (el backend normaliza)
    required String fechaInicio,     // 'YYYY-MM-DD'
    required int numCuotas,          // ej: 2
    required double tasaInteres,     // ej: 10.0
  }) async {
    final body = {
      'cod_cli': codCli.trim(),
      'monto': monto,
      'modalidad': modalidad,
      'fecha_inicio': fechaInicio,
      'num_cuotas': numCuotas,
      'tasa_interes': tasaInteres,
    };
    final resp = await _dio.post('/prestamos', data: body);
    return Map<String, dynamic>.from(resp.data as Map);
  }

  // -----------------------------
  // Métodos con nombres en español (compatibilidad con pantallas existentes)
  // -----------------------------
  Future<Map<String, dynamic>> listar({
    String? codCli,
    int page = 1,
    int pageSize = 20,
  }) => list(page: page, pageSize: pageSize, codCli: codCli);

  Future<Map<String, dynamic>> obtener(int id) => getById(id);

  Future<Map<String, dynamic>> crear({
    required String codCli,
    required double monto,
    required String modalidad,
    required String fechaInicio,
    required int numCuotas,
    required double tasaInteres,
  }) => create(
        codCli: codCli,
        monto: monto,
        modalidad: modalidad,
        fechaInicio: fechaInicio,
        numCuotas: numCuotas,
        tasaInteres: tasaInteres,
      );
}
