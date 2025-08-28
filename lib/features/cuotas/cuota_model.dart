// lib/features/cuotas/cuota_model.dart
class Cuota {
  final int id;
  final int idPrestamo;
  final int? numero;
  final String? fechaVencimiento;
  final String estado;
  final double? interesAPagar;
  final double? interesPagado;
  final int? diasMora;
  final double? abonoCapital;

  Cuota({
    required this.id,
    required this.idPrestamo,
    this.numero,
    this.fechaVencimiento,
    required this.estado,
    this.interesAPagar,
    this.interesPagado,
    this.diasMora,
    this.abonoCapital,
  });

  factory Cuota.fromJson(Map<String, dynamic> j){
    int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
    double? _f(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
    return Cuota(
      id: j['id'] as int,
      idPrestamo: (j['id_prestamo'] ?? j['prestamo_id']) as int,
      numero: _i(j['cuota_numero'] ?? j['numero']),
      fechaVencimiento: j['fecha_vencimiento'] as String?,
      estado: (j['estado'] as String?) ?? 'PENDIENTE',
      interesAPagar: _f(j['interes_a_pagar'] ?? j['interes']),
      interesPagado: _f(j['interes_pagado']),
      diasMora: _i(j['dias_mora']),
      abonoCapital: _f(j['abono_capital']),
    );
  }
}