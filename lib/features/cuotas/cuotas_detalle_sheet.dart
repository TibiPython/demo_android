// lib/features/cuotas/cuotas_detalle_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'cuotas_service.dart';
import 'cuota_model.dart';
import 'cuota_pago_dialog.dart';
import 'abono_capital_dialog.dart';

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
      builder: (_, controller) => CuotasDetalleSheet(prestamoId: prestamoId, scrollController: controller),
    ),
  );
}

class CuotasDetalleSheet extends ConsumerWidget {
  final int prestamoId;
  final ScrollController scrollController;
  const CuotasDetalleSheet({super.key, required this.prestamoId, required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(cuotasServiceProvider);
    final fmtCop = NumberFormat.currency(locale: 'es_CO', symbol: '\$');
    final fmtDate = DateFormat('yyyy-MM-dd');

    return FutureBuilder<Map<String, dynamic>>(
      future: service.obtenerResumenDePrestamo(prestamoId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ));
        }
        if (snap.hasError || snap.data == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Error cargando préstamo #$prestamoId', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${snap.error ?? 'Sin datos'}'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
              ],
            ),
          );
        }

        final resumen = snap.data!['resumen'] as Map<String, dynamic>;
        final cuotas = (snap.data!['cuotas'] as List).cast<Map<String, dynamic>>();
        final modalidad = resumen['modalidad'] as String?;
        final importe = (resumen['importe_credito'] as num?)?.toDouble() ?? 0.0;
        final tasa = (resumen['tasa_interes'] as num?)?.toDouble();
        final totalInteres = (resumen['total_interes_a_pagar'] as num?)?.toDouble() ?? 0.0;
        final totalAbonos = (resumen['total_abonos_capital'] as num?)?.toDouble() ?? 0.0;
        final totalConInteres = importe + totalInteres;

        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Préstamo #$prestamoId — ${resumen['nombre_cliente'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: [
                _kv('Modalidad', modalidad ?? '-'),
                _kv('Tasa (%)', tasa == null ? '-' : tasa.toString()),
                _kv('Prestado', fmtCop.format(importe)),
                _kv('Interés a pagar (total)', fmtCop.format(totalInteres)),
                _kv('Prestado + Interés', fmtCop.format(totalConInteres)),
                _kv('Abonos a capital (total)', fmtCop.format(totalAbonos)),
              ]),
              const SizedBox(height: 16),
              Text('Cuotas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cuotas.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = cuotas[i];
                  final idCuota = c['id'] as int;
                  final numCuota = c['cuota_numero']?.toString() ?? '-';
                  final venc = (c['fecha_vencimiento'] as String?);
                  final interes = (c['interes_a_pagar'] as num?)?.toDouble() ?? 0.0;
                  final estado = (c['estado'] as String?) ?? 'PENDIENTE';
                  final diasMora = (c['dias_mora'] as int?) ?? 0;
                  return ListTile(
                    leading: CircleAvatar(child: Text(numCuota)),
                    title: Text('Vence: ${venc ?? '-'}  ·  Estado: $estado  ·  Mora: ${diasMora}d'),
                    subtitle: Text('Interés a pagar: ${fmtCop.format(interes)}'),
                    trailing: Wrap(spacing: 8, children: [
                      if (estado == 'PENDIENTE')
                        ElevatedButton(
                          onPressed: () async {
                            final pr = await showPagoCuotaDialog(context, sugerido: interes);
                            if (pr != null) {
                              try {
                                await service.pagarCuota(idCuota, interesPagado: pr.interesPagado, fechaPago: pr.fechaPago);
                                // Cerrar devolviendo true para recargar lista principal
                                // ignore: use_build_context_synchronously
                                Navigator.pop(context, true);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al pagar: $e')));
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
                              await service.abonarCapital(idCuota, ar.monto, fecha: ar.fecha);
                              // ignore: use_build_context_synchronously
                              Navigator.pop(context, true);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al abonar: $e')));
                              }
                            }
                          }
                        },
                        child: const Text('Abono capital'),
                      ),
                    ]),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) => Chip(label: Text('$k: $v'));
}