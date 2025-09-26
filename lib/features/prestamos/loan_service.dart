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

  // ================== helpers internos ==================
  String _dateOnlyFromDynamic(dynamic d) {
    if (d is DateTime) return d.toIso8601String().split('T').first;
    if (d is String) {
      // Se asume 'yyyy-MM-dd' si ya viene formateado desde la UI
      return d;
    }
    throw ArgumentError('fechaInicio debe ser DateTime o String yyyy-MM-dd');
  }

  Map<String, dynamic> _toJsonMap(dynamic data) =>
      (data is Map<String, dynamic>) ? data : <String, dynamic>{};

  // ================== listado ==================
  Future<Map<String, dynamic>> list({
    int page = 1,
    int pageSize = 20,
    String? codCli,
  }) async {
    final resp = await _dio.get(
      '/prestamos',
      queryParameters: <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        if (codCli != null && codCli.trim().isNotEmpty) 'cod_cli': codCli.trim(),
      },
    );
    return _toJsonMap(resp.data);
  }

  // ================== cabecera/detalle ==================
  Future<Map<String, dynamic>> getById(int id) async {
    final resp = await _dio.get('/prestamos/$id');
    return _toJsonMap(resp.data);
  }

  // ================== plan / resumen ==================
  Future<Map<String, dynamic>> getResumenByPrestamoId(int id) async {
    final resp = await _dio.get('/prestamos/$id/plan');
    return _toJsonMap(resp.data);
  }

  // ================== crear AUTOMÁTICO ==================
  Future<Map<String, dynamic>> create({
    required String codCli,
    required double monto,
    required String modalidad,           // 'Mensual' | 'Quincenal'
    required dynamic fechaInicio,        // String 'yyyy-MM-dd' o DateTime
    required int numCuotas,
    required double tasaInteres,
  }) async {
    final resp = await _dio.post(
      '/prestamos',
      data: <String, dynamic>{
        'cod_cli': codCli.trim(),
        'monto': monto,
        'modalidad': modalidad,
        'fecha_inicio': _dateOnlyFromDynamic(fechaInicio),
        'num_cuotas': numCuotas,
        'tasa_interes': tasaInteres,
      },
    );
    return _toJsonMap(resp.data);
  }

  // ================== crear MANUAL ==================
  Future<Map<String, dynamic>> createManual({
    required String codCli,
    required double monto,
    required String modalidad,            // 'Mensual' | 'Quincenal'
    required dynamic fechaInicio,         // String 'yyyy-MM-dd' o DateTime
    required int numCuotas,
    required double tasa,                 // backend lo guarda en tasa_interes
    required List<Map<String, dynamic>> plan, // [{capital, interes}]
  }) async {
    // normalizar a números
    final normalizedPlan = plan.map((e) {
      double toNum(v) {
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0.0;
      }
      return <String, dynamic>{
        'capital': toNum(e['capital']),
        'interes': toNum(e['interes']),
      };
    }).toList();

    final resp = await _dio.post(
      '/prestamos/manual',
      data: <String, dynamic>{
        'cod_cli': codCli.trim(),
        'monto': monto,
        'modalidad': modalidad,
        'fecha_inicio': _dateOnlyFromDynamic(fechaInicio),
        'num_cuotas': numCuotas,
        'tasa': tasa,
        'plan': normalizedPlan,
      },
    );
    return _toJsonMap(resp.data);
  }

  // ================== actualizar AUTOMÁTICO ==================
  Future<Map<String, dynamic>> update({
    required int id,
    required String codCli,
    required double monto,
    required String modalidad,
    required dynamic fechaInicio,        // String 'yyyy-MM-dd' o DateTime
    required int numCuotas,
    required double tasaInteres,
  }) async {
    final resp = await _dio.put(
      '/prestamos/$id',
      data: <String, dynamic>{
        'cod_cli': codCli.trim(),
        'monto': monto,
        'modalidad': modalidad,
        'fecha_inicio': _dateOnlyFromDynamic(fechaInicio),
        'num_cuotas': numCuotas,
        'tasa_interes': tasaInteres,
      },
    );
    return _toJsonMap(resp.data);
  }

  // ================== replan (modo manual) ==================
  Future<Map<String, dynamic>> replanPrestamo({
    required int id,
    String? modalidad, // opcional
    required List<Map<String, dynamic>> plan, // [{capital, interes}]
  }) async {
    final normalizedPlan = plan.map((e) {
      double toNum(v) {
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? 0.0;
      }
      return <String, dynamic>{
        'capital': toNum(e['capital']),
        'interes': toNum(e['interes']),
      };
    }).toList();

    final body = <String, dynamic>{
      if (modalidad != null) 'modalidad': modalidad,
      'plan': normalizedPlan,
    };

    final resp = await _dio.put('/prestamos/$id/replan', data: body);
    return _toJsonMap(resp.data);
  }

  // ================== Aliases conservadores (compat UI) ==================
  Future<Map<String, dynamic>> listar({String? codCli, int page = 1, int pageSize = 20}) =>
      list(page: page, pageSize: pageSize, codCli: codCli);

  Future<Map<String, dynamic>> obtener(int id) => getById(id);

  Future<Map<String, dynamic>> obtenerResumen(int id) => getResumenByPrestamoId(id);

  // alias histórico (crear auto)
  Future<Map<String, dynamic>> crear({
    required String codCli,
    required double monto,
    required String modalidad,
    required dynamic fechaInicio, // String o DateTime
    required int numCuotas,
    required double tasaInteres,
  }) =>
      create(
        codCli: codCli,
        monto: monto,
        modalidad: modalidad,
        fechaInicio: fechaInicio,
        numCuotas: numCuotas,
        tasaInteres: tasaInteres,
      );

  // alias del método manual con el nombre que usa tu UI
  Future<Map<String, dynamic>> crearManual({
    required String codCli,
    required double monto,
    required double tasa,
    required String modalidad,
    required int numCuotas,
    required dynamic fechaInicio, // String o DateTime
    required List<Map<String, dynamic>> plan,
  }) =>
      createManual(
        codCli: codCli,
        monto: monto,
        tasa: tasa,
        modalidad: modalidad,
        numCuotas: numCuotas,
        fechaInicio: fechaInicio,
        plan: plan,
      );

  // usados por loan_edit_page.dart
  Future<Map<String, dynamic>> obtenerPlan(int prestamoId) => getResumenByPrestamoId(prestamoId);

  Future<Map<String, dynamic>> actualizarPrestamoAuto({
    required int id,
    required String codCli,
    required double monto,
    required String modalidad,
    required dynamic fechaInicio, // String o DateTime
    required int numCuotas,
    required double tasaInteres,
  }) =>
      update(
        id: id,
        codCli: codCli,
        monto: monto,
        modalidad: modalidad,
        fechaInicio: fechaInicio,
        numCuotas: numCuotas,
        tasaInteres: tasaInteres,
      );

  // La UI a veces envía más datos de los que requiere el replan manual;
  // los aceptamos para compatibilidad y los ignoramos si no aplican.
  Future<Map<String, dynamic>> actualizarPrestamoManual({
    required int id,
    String? codCli,          // ignorado por backend en replan
    double? monto,           // ignorado
    String? modalidad,       // si viene, lo pasamos al replan
    dynamic fechaInicio,     // ignorado
    int? numCuotas,          // ignorado
    double? tasa,            // ignorado
    required List<Map<String, dynamic>> plan,
  }) =>
      replanPrestamo(
        id: id,
        modalidad: modalidad,
        plan: plan,
      );
}


// ================== ESTADO (adiciones mínimas; sin tocar líneas existentes) ==================
// Preferimos las nuevas rutas del backend y hacemos fallback a las alternativas.
// - /prestamos/estado/{id}             (backend/app/routers/prestamos.py)
// - /prestamos/estado?ids=1,2,3
// Fallbacks (si existen):
// - /cuotas/estado/prestamo/{id}       (backend/app/routers/cuotas.py)
// - /cuotas/estado/resumen-prestamos?ids=1,2,3

extension PrestamosApiEstado on PrestamosApi {
  Future<Map<String, dynamic>> getEstadoByPrestamoId(int id) async {
    Map<String, dynamic> _asMap(dynamic d) =>
        (d is Map<String, dynamic>) ? d : <String, dynamic>{};
    try {
      final resp = await _dio.get('/prestamos/estado/$id');
      return _asMap(resp.data);
    } on DioException {
      // fallback a cuotas si la ruta no existe aún
      final resp = await _dio.get('/cuotas/estado/prestamo/$id');
      return _asMap(resp.data);
    }
  }

  Future<List<Map<String, dynamic>>> getEstadosByIds(List<int> ids) async {
    List<Map<String, dynamic>> _asList(dynamic d) {
      if (d is List) {
        return d.map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) return e;
          return <String, dynamic>{};
        }).toList();
      }
      return const <Map<String, dynamic>>[];
    }

    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    final idsParam = ids.join(',');

    try {
      final resp = await _dio.get('/prestamos/estado', queryParameters: {'ids': idsParam});
      return _asList(resp.data);
    } on DioException {
      // fallback a cuotas si la ruta no existe aún
      final resp = await _dio.get('/cuotas/estado/resumen-prestamos', queryParameters: {'ids': idsParam});
      return _asList(resp.data);
    }
  }

  // Aliases conservadores para la UI en español
  Future<Map<String, dynamic>> obtenerEstado(int id) => getEstadoByPrestamoId(id);
  Future<List<Map<String, dynamic>>> listarEstados(List<int> ids) => getEstadosByIds(ids);
}
