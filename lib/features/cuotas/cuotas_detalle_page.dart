// lib/features/cuotas/cuotas_detalle_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cuotas_service.dart';
import 'cuota_pago_dialog.dart';
import 'abono_capital_dialog.dart';

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
  final fmtMoney = NumberFormat.currency(locale: 'es_CO', symbol: r'$');

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
    return _DetalleData(resumen: resumen, cuotas: cuotas);
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
                          Text(
                            r.nombreCliente ?? '',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _kv('Modalidad', r.modalidad ?? '-'),
                              _kv(
                                'Vence',
                                r.venceUltimaCuota == null
                                    ? '-'
                                    : fmtDate.format(r.venceUltimaCuota!),
                              ),
                              _kv(
                                'Crédito',
                                r.importeCredito == null
                                    ? '-'
                                    : fmtMoney.format(r.importeCredito),
                              ),
                              _kv('Tasa %', r.tasaInteres?.toStringAsFixed(2) ?? '-'),
                              _kv('Interés total', fmtMoney.format(r.totalInteresAPagar)),
                              _kv('Abonos capital', fmtMoney.format(r.totalAbonosCapital)),
                              _kv('Capital pendiente', fmtMoney.format(r.capitalPendiente)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Chip(
                        label: Text(r.estado),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        backgroundColor: _estadoColor(r.estado).withOpacity(0.15),
                        side: BorderSide(
                          color: _estadoColor(r.estado).withOpacity(0.25),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ----- Tarjetas de Cuotas -----
              ...data.cuotas.map((q) => _CuotaCard(
                    q: q,
                    fmtDate: fmtDate,
                    fmtMoney: fmtMoney,
                    estadoColor: _estadoColor,
                    onPagar: (double interes, DateTime? fecha) async {
                      await service.pagarCuota(
                        q['id'] as int,
                        interesPagado: interes,
                        fechaPago: fecha,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pago registrado')),
                        );
                        _reload();
                      }
                    },
                    onAbono: (double monto, DateTime? fecha) async {
                      await service.abonarCapital(
                        q['id'] as int,
                        monto,
                        fecha: fecha,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Abono registrado')),
                        );
                        _reload();
                      }
                    },
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(v),
      ],
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

  const _CuotaCard({
    super.key,
    required this.q,
    required this.fmtDate,
    required this.fmtMoney,
    required this.estadoColor,
    required this.onPagar,
    required this.onAbono,
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
            // Encabezado
            Row(
              children: [
                CircleAvatar(child: Text(numTxt)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cuota $numTxt  ·  $modTxt',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
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

            // Dos columnas: Vence / Mora (días)
            Row(
              children: [
                Expanded(child: Text('Vence: ${_fmt(q['fecha_vencimiento'])}')),
                Expanded(child: Text('Mora (días): ${moraTxt.isEmpty ? "0" : moraTxt}')),
              ],
            ),
            // 👇 Mostramos Fecha de pago justo debajo de Vence (si existe)
            if (_s(q['fecha_pago']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Fecha de pago: ${_fmt(q["fecha_pago"])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

            const SizedBox(height: 8),

            // Dos columnas: Interés a pagar / Interés pagado
            Row(
              children: [
                Expanded(child: Text('Interés a pagar: ${fmtMoney.format(interesAPagar)}')),
                Expanded(child: Text('Interés pagado: ${fmtMoney.format(interesPagado)}')),
              ],
            ),
            const SizedBox(height: 8),

            // Dos columnas: Abono capital / ID cuota
            Row(
              children: [
                Expanded(child: Text('Abono capital: ${fmtMoney.format(abonoCapital)}')),
                Expanded(child: Text('ID cuota: ${_s(idCuota)}')),
              ],
            ),
            const SizedBox(height: 16),

            // Acciones (mantiene icono cerdito en Abono)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (estado == 'PENDIENTE')
                  ElevatedButton(
                    onPressed: () async {
                      final sugerido = (interesAPagar as num).toDouble();
                      final result = await showPagoCuotaDialog(context, sugerido: sugerido);
                      if (result == null) return;
                      await onPagar(result.interesPagado, result.fechaPago);
                    },
                    child: const Text('Pagar interés'),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await showAbonoCapitalDialog(context);
                    if (result == null) return;
                    await onAbono((result.monto as num).toDouble(), result.fecha);
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
  _DetalleData({required this.resumen, required this.cuotas});
}
