import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:demo_android/core/safe_close.dart';
import 'cuotas_service.dart';
import 'cuota_model.dart';
import 'cuota_pago_dialog.dart';
import 'abono_capital_dialog.dart';

String _pf(num? v) {
  if (v == null) return '-';
  final s = NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 2).format(v);
  return '\$ ' + s;
}



Future<bool?> showCuotasDetalleSheet(BuildContext context, {required int prestamoId}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => CuotasDetalleSheet(
        prestamoId: prestamoId,
        scrollController: controller,
      ),
    ),
  );
}

class CuotasDetalleSheet extends ConsumerWidget {
  final int prestamoId;
  final ScrollController scrollController;
  const CuotasDetalleSheet({
    super.key,
    required this.prestamoId,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(cuotasServiceProvider);
    final fmt = NumberFormat.currency(locale: 'es_CO', symbol: r'$');

    return FutureBuilder<Map<String, dynamic>>(
      future: service.obtenerResumenDePrestamo(prestamoId),
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

        final data = snap.data ?? const {};
        final resumen = (data['resumen'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final cuotas = (data['cuotas'] as List? ?? const []).cast<dynamic>().map((e) {
          return e is Cuota ? e : Cuota.fromJson((e as Map).cast<String, dynamic>());
        }).toList();

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: ListView(
            controller: scrollController,
            children: [
              // Resumen
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (resumen['cliente_nombre'] != null)
                    _chip('Cliente', resumen['cliente_nombre'].toString()),
                  if (resumen['estado'] != null)
                    _estadoChip(resumen['estado'].toString()),
                  if (resumen['importe_credito'] != null)
                    _chip('Crédito', _pf(_f(resumen['importe_credito']))),
                  if (resumen['tasa_interes'] != null)
                    _chip('Tasa %', _f(resumen['tasa_interes']).toStringAsFixed(2)),
                  if (resumen['total_interes_a_pagar'] != null)
                    _chip('Interés total', _pf(_f(resumen['total_interes_a_pagar']))),
                  if (resumen['total_abonos_capital'] != null)
                    _chip('Abonos cap.', _pf(_f(resumen['total_abonos_capital']))),
                  if (resumen['capital_pendiente'] != null)
                    _chip('Capital pendiente', _pf(_f(resumen['capital_pendiente']))),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),

              // Lista de cuotas
              ListView.separated(
                shrinkWrap: true,
                controller: scrollController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cuotas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = cuotas[i];
                  final idCuota = c.id;
                  final numCuota = c.numero?.toString() ?? '-';
                  final venc = c.fechaVencimiento ?? '-';
                  final interes = c.interesAPagar ?? 0.0;
                  final pagado = c.interesPagado ?? 0.0;
                  final estado = c.estado;
                  final diasMora = c.diasMora ?? 0;

                  return ListTile(
                    // leading eliminado para no mostrar el ID/numero en un círculo
                    title: Text('Vence: $venc  ·  Estado: $estado  ·  Mora: ${diasMora}d'),
                    subtitle: Text(
                      'Interés a pagar: ${_pf(interes)}  ·  Pagado: $${_pf(pagado)}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (estado == 'PENDIENTE')
                          ElevatedButton(
                            onPressed: () async {
                              final pr =
                                  await showPagoCuotaDialog(context, sugerido: interes);
                              if (pr != null) {
                                try {
                                  await service.pagarCuota(
                                    idCuota,
                                    interesPagado: pr.interesPagado,
                                    fechaPago: pr.fechaPago,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Pago registrado')),
                                    );
                                  }
                                  // Cerrar devolviendo true para recargar
                                  // ignore: use_build_context_synchronously
                                  await SafeClose.pop(context, true);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error al pagar: $e')),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Text('Pagar interés'),
                          ),
                        OutlinedButton(
                          onPressed: () async {
                            final ar = await showAbonoCapitalDialog(context);
                            if (ar != null) {
                              try {
                                await service.abonarCapital(
                                  idCuota,
                                  ar.monto,
                                  fecha: ar.fecha,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Abono registrado')),
                                  );
                                }
                                // Cerrar para recargar
                                // ignore: use_build_context_synchronously
                                await SafeClose.pop(context, true);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            }
                          },
                          child: const Text('Abono capital'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String k, String v) => Chip(label: Text('$k: $v'));

  Widget _estadoChip(String estado) {
    final e = estado.toUpperCase();
    Color bg, fg;
    switch (e) {
      case 'PAGADO':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
        break;
      case 'VENCIDO':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        break;
      default:
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFF9A3412);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(estado, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  double _f(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
}