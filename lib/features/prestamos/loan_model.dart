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
        id: j['id'] as int,
        numero: j['numero'] as int,
        fechaVencimiento: DateTime.parse(j['fecha_vencimiento'] as String),
        interesAPagar: (j['interes_a_pagar'] as num).toDouble(),
        interesPagado: (j['interes_pagado'] as num).toDouble(),
        estado: j['estado'] as String,
      );
}

class Prestamo {
  final int id;
  final Map<String, dynamic> cliente; // {id,codigo,nombre}
  final int monto;
  final String modalidad; // MENSUAL | QUINCENAL
  final DateTime fechaInicio;
  final int numCuotas;
  final double tasaInteres;
  final List<Cuota> cuotas;

  Prestamo({
    required this.id,
    required this.cliente,
    required this.monto,
    required this.modalidad,
    required this.fechaInicio,
    required this.numCuotas,
    required this.tasaInteres,
    required this.cuotas,
  });

  factory Prestamo.fromJson(Map<String, dynamic> j) => Prestamo(
        id: j['id'] as int,
        cliente: j['cliente'] as Map<String, dynamic>,
        monto: j['monto'] as int,
        modalidad: j['modalidad'] as String,
        fechaInicio: DateTime.parse(j['fecha_inicio'] as String),
        numCuotas: j['num_cuotas'] as int,
        tasaInteres: (j['tasa_interes'] as num).toDouble(),
        cuotas: (j['cuotas'] as List).map((e) => Cuota.fromJson(e)).toList(),
      );
}

class PrestamoItem {
  final int id;
  final Map<String, dynamic> cliente; // {id,codigo,nombre}
  final int monto;
  final String modalidad;
  final DateTime fechaInicio;
  final int numCuotas;
  final double tasaInteres;

  PrestamoItem({
    required this.id,
    required this.cliente,
    required this.monto,
    required this.modalidad,
    required this.fechaInicio,
    required this.numCuotas,
    required this.tasaInteres,
  });

  factory PrestamoItem.fromJson(Map<String, dynamic> j) => PrestamoItem(
        id: j['id'] as int,
        cliente: j['cliente'] as Map<String, dynamic>,
        monto: j['monto'] as int,
        modalidad: j['modalidad'] as String,
        fechaInicio: DateTime.parse(j['fecha_inicio'] as String),
        numCuotas: j['num_cuotas'] as int,
        tasaInteres: (j['tasa_interes'] as num).toDouble(),
      );
}

class PrestamosResp {
  final int total;
  final List<PrestamoItem> items;
  PrestamosResp({required this.total, required this.items});

  factory PrestamosResp.fromJson(Map<String, dynamic> j) => PrestamosResp(
        total: j['total'] as int,
        items: (j['items'] as List).map((e) => PrestamoItem.fromJson(e)).toList(),
      );
}
