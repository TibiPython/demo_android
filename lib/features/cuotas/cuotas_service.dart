// lib/features/cuotas/cuotas_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:demo_android/core/api.dart'; // usa dioProvider con baseUrl = kBaseUrl
import 'cuota_model.dart';

/// Provider: inyecta el Dio configurado en core/api.dart
final cuotasServiceProvider = Provider<CuotasService>((ref) {
  final dio = ref.read(dioProvider);
  return CuotasService(dio);
});

/// DTO para el resumen por préstamo (coincide con el backend /cuotas/resumen-prestamos)
class PrestamoResumen {
  final int id;
  final String? nombreCliente;
  final DateTime? venceUltimaCuota;
  final String estado;               // PENDIENTE / PAGADO / VENCIDO
  final String? modalidad;
  final double? importeCredito;
  final double? tasaInteres;
  final double totalInteresAPagar;
  final double totalAbonosCapital;
  final double capitalPendiente;

  PrestamoResumen({
    required this.id,
    required this.nombreCliente,
    required this.venceUltimaCuota,
    required this.estado,
    this.modalidad,
    this.importeCredito,
    this.tasaInteres,
    required this.totalInteresAPagar,
    required this.totalAbonosCapital,
    required this.capitalPendiente,
  });

  factory PrestamoResumen.fromJson(Map<String, dynamic> j) {
    DateTime? _d(dynamic s) {
      if (s == null) return null;
      final str = s.toString();
      if (str.isEmpty) return null;
      return DateTime.parse(str);
    }

    double _f(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    double? _fNullable(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return PrestamoResumen(
      id: (j['id'] as num).toInt(),
      nombreCliente: j['nombre_cliente'] as String?,
      venceUltimaCuota: _d(j['vence_ultima_cuota']),
      estado: (j['estado'] as String?) ?? 'PENDIENTE',
      modalidad: j['modalidad'] as String?,
      importeCredito: _fNullable(j['importe_credito']),
      tasaInteres: _fNullable(j['tasa_interes']),
      totalInteresAPagar: _f(j['total_interes_a_pagar']),
      totalAbonosCapital: _f(j['total_abonos_capital']),
      capitalPendiente: _f(j['capital_pendiente']),
    );
  }
}

class CuotasService {
  final Dio dio;
  CuotasService(this.dio);

  // ---- helpers ----
  Never _throwDio(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    throw Exception('Error ${code ?? ''}: ${data ?? e.message}');
  }

  // ---- endpoints ----

  /// GET /cuotas/resumen-prestamos
  Future<List<PrestamoResumen>> listarResumenPrestamos() async {
    try {
      final res = await dio.get('/cuotas/resumen-prestamos');
      final body = res.data;
      if (res.statusCode != 200 || body is! List) {
        throw Exception('Respuesta inesperada: ${res.statusCode} ${res.data}');
      }
      return body
          .map<PrestamoResumen>((e) => PrestamoResumen.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// GET /cuotas/prestamo/{id}/resumen
  /// Devuelve el mapa con:
  ///  { "resumen": {...}, "cuotas": [ {...}, ... ] }
  Future<Map<String, dynamic>> obtenerResumenDePrestamo(int prestamoId) async {
    try {
      final res = await dio.get('/cuotas/prestamo/$prestamoId/resumen');
      if (res.statusCode != 200) {
        throw Exception('Error ${res.statusCode}: ${res.data}');
      }
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// POST /cuotas/{cuotaId}/pago
  /// Retorna la cuota actualizada.
  Future<Cuota> pagarCuota(
    int cuotaId, {
    required double interesPagado,
    DateTime? fechaPago,
  }) async {
    try {
      final payload = <String, dynamic>{
        'interes_pagado': interesPagado,
        if (fechaPago != null) 'fecha_pago': fechaPago.toIso8601String().substring(0, 10),
      };
      final res = await dio.post('/cuotas/$cuotaId/pago', data: payload);
      if (res.statusCode != 200 || res.data is! Map) {
        throw Exception('Respuesta inesperada: ${res.statusCode} ${res.data}');
      }
      return Cuota.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  /// POST /cuotas/{cuotaId}/abono-capital
  Future<void> abonarCapital(
    int cuotaId,
    double monto, {
    DateTime? fecha,
  }) async {
    try {
      final payload = <String, dynamic>{
        'monto': monto,
        if (fecha != null) 'fecha': fecha.toIso8601String().substring(0, 10),
      };
      final res = await dio.post('/cuotas/$cuotaId/abono-capital', data: payload);
      if (res.statusCode != 200) {
        throw Exception('Error ${res.statusCode}: ${res.data}');
      }
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  // --- OPCIONAL (no rompe nada): listar cuotas de un préstamo con el endpoint general
  Future<List<Cuota>> listarCuotasDePrestamo(int prestamoId) async {
    try {
      final res = await dio.get('/cuotas', queryParameters: {'id_prestamo': prestamoId});
      final body = res.data;
      if (res.statusCode != 200 || body is! List) {
        throw Exception('Respuesta inesperada: ${res.statusCode} ${res.data}');
      }
      return body.map<Cuota>((e) => Cuota.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _throwDio(e);
    }
  }
}


// ================== Adiciones mínimas: estado canónico por Cuotas (fallback) ==================
// Estas utilidades NO reemplazan nada existente. Proveen acceso a las rutas de estado
// en el router de cuotas para usarse como respaldo cuando el router de préstamos no esté disponible.
// - GET /cuotas/estado/prestamo/{id}
// - GET /cuotas/estado/resumen-prestamos?ids=1,2,3

extension CuotasServiceEstadoX on CuotasService {
  Future<Map<String, dynamic>> obtenerEstadoPrestamo(int prestamoId) async {
    try {
      final res = await dio.get('/cuotas/estado/prestamo/$prestamoId');
      final body = res.data;
      if (res.statusCode != 200 || body is! Map) {
        throw Exception('Respuesta inesperada: ${res.statusCode} ${res.data}');
      }
      return Map<String, dynamic>.from(body as Map);
    } on DioException catch (e) {
      _throwDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> listarEstadosPrestamos(List<int> ids) async {
    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    final idsParam = ids.join(',');
    try {
      final res = await dio.get('/cuotas/estado/resumen-prestamos', queryParameters: {'ids': idsParam});
      final body = res.data;
      if (res.statusCode != 200 || body is! List) {
        throw Exception('Respuesta inesperada: ${res.statusCode} ${res.data}');
      }
      return (body as List)
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } on DioException catch (e) {
      _throwDio(e);
    }
  }
}
