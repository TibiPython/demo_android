import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cuotas_service.dart';
import 'cuota_pago_dialog.dart';
import 'abono_capital_dialog.dart';

// Bus de refresh (no cambia comportamiento existente)
import 'package:demo_android/features/prestamos/refresh_bus.dart';

String _pf(num? v) {
  if (v == null) return '-';
  final s = NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 2).format(v);
  return '\$\u00A0' + s;
}

class CuotasDetallePage extends ConsumerStatefulWidget {
  final int prestamoId;
  const CuotasDetallePage({super.key, required this.prestamoId});

  @override
  ConsumerState<CuotasDetallePage> createState() => _CuotasDetallePageState();
}

class _CuotasDetallePageState extends ConsumerState<CuotasDetallePage> {
  late CuotasService service;
  late Future<_DetalleData> future;

  final fmtDate = DateFormat('yyyy-MM-dd');
  final fmtMoney = NumberFormat.currency(locale: 'es_CO', symbol: '');

  @override
  void initState() {
    super.initState();
    service = ref.read(cuotasServiceProvider);
    future = _load();
  }

  Future<_DetalleData> _load() async {
    final raw = await service.obtenerResumenDePrestamo(widget.prestamoId);
    final resumenJson = (raw['resumen'] as Map<String, dynamic>);
    final resumen = PrestamoResumen.fromJson(resumenJson);
    final cuotas = List<Map<String, dynamic>>.from(raw['cuotas'] as List);
    
String? estadoCanonico;
try {
  final est = await service.obtenerEstadoPrestamo(widget.prestamoId);
  final e = (est['estado'] ?? '').toString();
  if (e.isNotEmpty) estadoCanonico = e.toUpperCase();
} catch (_) {}
return _DetalleData(resumen: resumen, cuotas: cuotas, estadoCanonico: estadoCanonico);

  }

  void _reload() {
    setState(() {
      future = _load();
    });
  }

  Color _estadoColor(String e) {
    switch ((e).toUpperCase()) {
      case 'PAGADO':
        return Colors.green;
      case 'VENCIDO':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  /// Deriva la fecha "Vence" para el header: prefiere la del resumen si es válida;
  /// si no, toma el máximo de las fechas de vencimiento de las cuotas.
  DateTime? _deriveVenceHeader(PrestamoResumen r, List<Map<String, dynamic>> cuotas) {
    DateTime? vence = r.venceUltimaCuota;
    // Si el resumen viene vacío o inconsistente, mirar cuotas:
    for (final c in cuotas) {
      final v = c['fecha_vencimiento']?.toString();
      if (v == null || v.isEmpty) continue;
      final d = DateTime.tryParse(v);
      if (d != null && (vence == null || d.isAfter(vence))) {
        vence = d;
      }
    }
    return vence;
  }

  /// Deriva el estado del header a partir de las cuotas:
  /// - Si alguna está VENCIDO -> VENCIDO
  /// - Si todas están PAGADO (y hay al menos una) -> PAGADO
  /// - En otro caso -> PENDIENTE
  String _deriveEstadoHeader(PrestamoResumen r, List<Map<String, dynamic>> cuotas) {
    bool anyVencido = false;
    bool allPagado = cuotas.isNotEmpty;
    for (final c in cuotas) {
      final e = (c['estado'] ?? '').toString().toUpperCase();
      if (e == 'VENCIDO') anyVencido = true;
      if (e != 'PAGADO') allPagado = false;
    }
    if (anyVencido) return 'VENCIDO';
    if (allPagado) return 'PAGADO';
    return 'PENDIENTE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Préstamo #${widget.prestamoId}')),
      body: FutureBuilder<_DetalleData>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}'),
              ),
            );
          }

          final data = snap.data!;
          final r = data.resumen;
          final cuotas = data.cuotas;

          // ⬇️ Nuevas derivaciones seguras (solo UI)
          final venceHeader = _deriveVenceHeader(r, cuotas);
          final estadoHeader = data.estadoCanonico ?? _deriveEstadoHeader(r, cuotas);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            children: [
              // ----- Tarjeta principal (header) -----
              Card(
                elevation: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 128, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.nombreCliente ?? '',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _kv(context, 'Modalidad', r.modalidad ?? '-'),
                              _kv(context, 'Vence', venceHeader == null ? '-' : fmtDate.format(venceHeader)),
                              _kv(context, 'Crédito',
                                  r.importeCredito == null ? '-' : _pf(r.importeCredito)),
                              _kv(context, 'Tasa %',
                                  r.tasaInteres?.toStringAsFixed(2) ?? '-'),
                              _kv(context, 'Interés total', _pf(r.totalInteresAPagar)),
                              _kv(context, 'Abonos capital', _pf(r.totalAbonosCapital)),
                              _kv(context, 'Capital pendiente', _pf(r.capitalPendiente)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Chip(
                        label: Text(estadoHeader),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        backgroundColor: _estadoColor(estadoHeader).withOpacity(0.15),
                        side: BorderSide(color: _estadoColor(estadoHeader).withOpacity(0.25)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ----- Tarjetas de Cuotas -----
              ...cuotas.map((q) => _CuotaCard(
                    q: q,
                    fmtDate: fmtDate,
                    fmtMoney: fmtMoney,
                    estadoColor: _estadoColor,
                    onPagar: (double interes, DateTime? fecha) async {
                      await service.pagarCuota(q['id'] as int, interesPagado: interes, fechaPago: fecha);
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Pago registrado')));
                        announcePrestamosRefresh(ref);
                        _reload();
                      }
                    },
                    onAbono: (double monto, DateTime? fecha) async {
                      await service.abonarCapital(q['id'] as int, monto, fecha: fecha);
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Abono registrado')));
                        announcePrestamosRefresh(ref);
                        _reload();
                      }
                    },
                    capitalMax: r.capitalPendiente,
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium!;
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '$k: ', style: baseStyle.copyWith(fontWeight: FontWeight.w600)),
          TextSpan(text: v),
        ],
      ),
      softWrap: true,
    );
  }
}

class _CuotaCard extends StatelessWidget {
  final Map<String, dynamic> q;
  final DateFormat fmtDate;
  final NumberFormat fmtMoney;
  final Color Function(String) estadoColor;
  final Future<void> Function(double interes, DateTime? fecha) onPagar;
  final Future<void> Function(double monto, DateTime? fecha) onAbono;
  final double? capitalMax;

  const _CuotaCard({
    super.key,
    required this.q,
    required this.fmtDate,
    required this.fmtMoney,
    required this.estadoColor,
    required this.onPagar,
    required this.onAbono,
    this.capitalMax,
  });

  @override
  Widget build(BuildContext context) {
    String _s(dynamic v) => (v ?? '').toString();

    String _fmt(dynamic v) {
      if (v == null) return '-';
      final s = v.toString();
      try {
        return fmtDate.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    final numTxt = _s(q['cuota_numero'] ?? q['numero']);
    final modTxt = _s(q['modalidad']);
    final estado = _s(q['estado']).toUpperCase();
    final moraTxt = _s(q['dias_mora']);
    final interesAPagar = (q['interes_a_pagar'] ?? 0);
    final interesPagado = (q['interes_pagado'] ?? 0);
    final abonoCapital = (q['abono_capital'] ?? 0);
    final idCuota = q['id'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(numTxt)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Cuota $numTxt  ·  $modTxt',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Chip(
                  label: Text(estado),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  backgroundColor: estadoColor(estado).withOpacity(0.15),
                  side: BorderSide(color: estadoColor(estado).withOpacity(0.25)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Vence: ${_fmt(q['fecha_vencimiento'])}')),
                Expanded(child: Text('Mora (días): ${moraTxt.isEmpty ? "0" : moraTxt}')),
              ],
            ),
            if (_s(q['fecha_pago']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Fecha de pago: ${_fmt(q["fecha_pago"])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Interés a pagar: ${_pf(interesAPagar)}')),
                Expanded(child: Text('Interés pagado: ${_pf(interesPagado)}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Abono capital: ${_pf(abonoCapital)}')),
                Expanded(child: Text('ID cuota: ${_s(idCuota)}')),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (estado == 'PENDIENTE')
                  ElevatedButton(
                    onPressed: () async {
                      final sugerido = (interesAPagar as num).toDouble();
                      final pr = await showPagoCuotaDialog(context, sugerido: sugerido);
                      if (pr != null) await onPagar(pr.interesPagado, pr.fechaPago);
                    },
                    child: const Text('Pagar interés'),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ar = await showAbonoCapitalDialog(context, capitalMax: capitalMax);
                    if (ar != null) await onAbono((ar.monto as num).toDouble(), ar.fecha);
                  },
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Abono'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _DetalleData {
  final PrestamoResumen resumen;
  final List<Map<String, dynamic>> cuotas;
  final String? estadoCanonico;
  _DetalleData({required this.resumen, required this.cuotas, this.estadoCanonico});
}

