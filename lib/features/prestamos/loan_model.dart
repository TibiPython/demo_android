// lib/features/prestamos/loan_model.dart
// Reemplazo mínimo y seguro:
// - 'monto' ahora es double en lugar de int para evitar errores de cast
// - parseo robusto con (value as num).toDouble()/toInt()
// - agrega 'estado' con fallback 'PENDIENTE'

class Cuota {
  final int id;
  final int numero;
  final DateTime fechaVencimiento;
  final double interesAPagar;
  final double interesPagado;
  final String estado;

  Cuota({
    required this.id,
    required this.numero,
    required this.fechaVencimiento,
    required this.interesAPagar,
    required this.interesPagado,
    required this.estado,
  });

  factory Cuota.fromJson(Map<String, dynamic> j) => Cuota(
        id: (j['id'] as num).toInt(),
        numero: (j['numero'] as num).toInt(),
        fechaVencimiento: DateTime.parse(j['fecha_vencimiento'] as String),
        interesAPagar: (j['interes_a_pagar'] as num).toDouble(),
        interesPagado: (j['interes_pagado'] as num).toDouble(),
        estado: (j['estado'] as String?) ?? 'PENDIENTE',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'numero': numero,
        'fecha_vencimiento': fechaVencimiento.toIso8601String(),
        'interes_a_pagar': interesAPagar,
        'interes_pagado': interesPagado,
        'estado': estado,
      };
}

class PrestamoItem {
  final int id;
  final Map<String, dynamic> cliente; // {id?, codigo, nombre}
  final double monto;                 // <- double para evitar cast error
  final String modalidad;
  final DateTime fechaInicio;
  final int numCuotas;
  final double tasaInteres;
  final String estado;

  PrestamoItem({
    required this.id,
    required this.cliente,
    required this.monto,
    required this.modalidad,
    required this.fechaInicio,
    required this.numCuotas,
    required this.tasaInteres,
    required this.estado,
  });

  factory PrestamoItem.fromJson(Map<String, dynamic> j) => PrestamoItem(
        id: (j['id'] as num).toInt(),
        cliente: Map<String, dynamic>.from(j['cliente'] as Map),
        monto: (j['monto'] as num).toDouble(),
        modalidad: j['modalidad'] as String,
        fechaInicio: DateTime.parse(j['fecha_inicio'] as String),
        numCuotas: (j['num_cuotas'] as num).toInt(),
        tasaInteres: (j['tasa_interes'] as num).toDouble(),
        estado: (j['estado'] as String?) ?? 'PENDIENTE',
      );
}

class Prestamo {
  final int id;
  final Map<String, dynamic> cliente;
  final double monto;                 // <- double para evitar cast error
  final String modalidad;
  final DateTime fechaInicio;
  final int numCuotas;
  final double tasaInteres;
  final String estado;
  final List<Cuota> cuotas;

  Prestamo({
    required this.id,
    required this.cliente,
    required this.monto,
    required this.modalidad,
    required this.fechaInicio,
    required this.numCuotas,
    required this.tasaInteres,
    required this.estado,
    required this.cuotas,
  });

  factory Prestamo.fromJson(Map<String, dynamic> j) => Prestamo(
        id: (j['id'] as num).toInt(),
        cliente: Map<String, dynamic>.from(j['cliente'] as Map),
        monto: (j['monto'] as num).toDouble(),
        modalidad: j['modalidad'] as String,
        fechaInicio: DateTime.parse(j['fecha_inicio'] as String),
        numCuotas: (j['num_cuotas'] as num).toInt(),
        tasaInteres: (j['tasa_interes'] as num).toDouble(),
        estado: (j['estado'] as String?) ?? 'PENDIENTE',
        cuotas: (j['cuotas'] as List)
            .map((e) => Cuota.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class PrestamosResp {
  final int total;
  final List<PrestamoItem> items;
  PrestamosResp({required this.total, required this.items});

  factory PrestamosResp.fromJson(Map<String, dynamic> j) => PrestamosResp(
        total: (j['total'] as num).toInt(),
        items: (j['items'] as List)
            .map((e) =>
                PrestamoItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
