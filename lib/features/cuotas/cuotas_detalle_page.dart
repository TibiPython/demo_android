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
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data!;
          final r = data.resumen;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Resumen del préstamo
                Card(
                  elevation: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
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
                            _kv('Modalidad', r.modalidad ?? '-'),
                            _kv('Vence', r.venceUltimaCuota == null
                                ? '-'
                                : fmtDate.format(r.venceUltimaCuota!)),
                            _chip('Estado', r.estado, _estadoColor(r.estado)),
                            _kv('Crédito', r.importeCredito == null
                                ? '-'
                                : fmtMoney.format(r.importeCredito)),
                            _kv('Tasa %', r.tasaInteres?.toStringAsFixed(2) ?? '-'),
                            _kv('Interés total', fmtMoney.format(r.totalInteresAPagar)),
                            _kv('Abonos capital', fmtMoney.format(r.totalAbonosCapital)),
                            _kv('Capital pendiente', fmtMoney.format(r.capitalPendiente)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Lista de cuotas en tarjetas: sin trailing (para evitar desbordes)
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
                        }
                        _reload();
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
                        }
                        _reload();
                      },
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Flexible(child: Text(v, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _chip(String k, String v, Color c) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('$k:', style: const TextStyle(fontWeight: FontWeight.w600)),
        Chip(label: Text(v), backgroundColor: c.withOpacity(0.15)),
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
    required this.q,
    required this.fmtDate,
    required this.fmtMoney,
    required this.estadoColor,
    required this.onPagar,
    required this.onAbono,
  });

  @override
  Widget build(BuildContext context) {
    String _s(dynamic v) => v == null ? '-' : v.toString();
    String venceTxt() {
      final s = q['fecha_vencimiento'] as String?;
      if (s == null || s.isEmpty) return '-';
      try {
        return fmtDate.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    final idCuota = q['id'] as int;
    final numTxt = _s(q['cuota_numero']);
    final modTxt = _s(q['modalidad']);
    final estado = _s(q['estado']).toUpperCase();
    final moraTxt = _s(q['dias_mora']);
    final interesAPagar = (q['interes_a_pagar'] ?? 0);
    final interesPagado = (q['interes_pagado'] ?? 0);
    final abonoCapital = (q['abono_capital'] ?? 0);

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
                //CircleAvatar(child: Text(numTxt)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cuota $numTxt · $modTxt',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Chip(
                  label: Text(estado),
                  backgroundColor: estadoColor(estado).withOpacity(0.15),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Datos en dos columnas responsivas (Table)
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _row('Vence', venceTxt(), 'Mora (días)', moraTxt),
                _row('Interés a pagar', fmtMoney.format(interesAPagar),
                    'Interés pagado', fmtMoney.format(interesPagado)),
                _row('Abono capital', fmtMoney.format(abonoCapital), 'ID cuota', '$idCuota'),
              ],
            ),

            const SizedBox(height: 8),

            // Acciones (abajo, sin usar trailing → evita desbordes)
            ButtonBar(
              alignment: MainAxisAlignment.end,
              overflowDirection: VerticalDirection.down,
              children: [
                if (estado != 'PAGADO')
                  ElevatedButton.icon(
                    onPressed: () async {
                      final res = await showPagoCuotaDialog(context);
                      if (res != null) {
                        await onPagar(res.interesPagado, res.fechaPago);
                      }
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Pagar'),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final res = await showAbonoCapitalDialog(context);
                    if (res != null) {
                      await onAbono(res.monto, res.fecha);
                    }
                  },
                  icon: const Icon(Icons.savings),
                  label: const Text('Abono'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _row(String k1, String v1, String k2, String v2) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _kv(k1, v1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _kv(k2, v2),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _DetalleData {
  final PrestamoResumen resumen;
  final List<Map<String, dynamic>> cuotas;
  _DetalleData({required this.resumen, required this.cuotas});
}
