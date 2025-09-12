// Pantalla principal de la lista de Préstamos (se importa desde main.dart).
// - FAB (+): SIEMPRE abre selector para crear préstamo Manual o Automático.
// - Botón Editar por ítem (habilitado si el préstamo NO está PAGADO).
// - Formato de moneda con símbolo adelante: $ 1.000.000,00

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/http.dart';
import '../loan_model.dart';
import '../loan_new_page.dart';            // creación automática (clásica)
import '../loan_service.dart';
import 'status_theme.dart';
import 'loan_new_manual_page.dart';       // creación manual (nueva)
import 'loan_edit_page.dart';             // edición/replan

class PrestamosListPage extends ConsumerStatefulWidget {
  const PrestamosListPage({super.key});

  @override
  ConsumerState<PrestamosListPage> createState() => _PrestamosListPageState();
}

class _PrestamosListPageState extends ConsumerState<PrestamosListPage> {
  late Future<PrestamosResp> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PrestamosResp> _load() async {
    final dio = ref.read(dioProvider);
    final res = await dio.get('/prestamos', queryParameters: {'page': 1, 'page_size': 100});
    return PrestamosResp.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> _openNewAuto(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoanNewPage()),
    );
    if (result == true && mounted) {
      setState(() => _future = _load());
    }
  }

  Future<void> _openNewManual(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoanNewManualPage()),
    );
    if (result == true && mounted) {
      setState(() => _future = _load());
    }
  }

  Future<void> _openNewChooser(BuildContext context) async {
    // Siempre mostrar el selector (sin 'recordar preferencia').
    String selected = 'manual';
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Crear préstamo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'manual',
                  groupValue: selected,
                  onChanged: (v) => setSt(() => selected = v!),
                  title: const Text('Manual (recomendado)'),
                  subtitle: const Text('Editar capital e interés por cuota; cierre verificado en la última.'),
                ),
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: selected,
                  onChanged: (v) => setSt(() => selected = v!),
                  title: const Text('Automático (clásico)'),
                  subtitle: const Text('Interés fijo por período; capital flexible.'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (selected == 'manual') {
                          await _openNewManual(context);
                        } else {
                          await _openNewAuto(context);
                        }
                      },
                      child: const Text('Continuar'),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final moneyFmt = NumberFormat.currency(locale: 'es_CO', symbol: r'$ ');
    return Scaffold(
      appBar: AppBar(title: const Text('Préstamos')),
      body: FutureBuilder<PrestamosResp>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = snap.data?.items ?? const <PrestamoItem>[];
          if (items.isEmpty) {
            return const Center(child: Text('No hay préstamos'));
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = items[i];
              final estado = it.estado;
              final nombre = (it.cliente['nombre'] ?? '').toString();
              final codigo = (it.cliente['codigo'] ?? '').toString();
              final monto = it.monto;

              // Estimar fecha de última cuota a partir de inicio + modalidad + n cuotas
              final dtFmt = DateFormat('yyyy-MM-dd');
              String venceTxt = '-';
              final int numCuotas = it.numCuotas;
              try {
                final DateTime fi = it.fechaInicio;
                if (it.modalidad == 'Mensual') {
                  final last = DateTime(fi.year, fi.month + numCuotas, fi.day);
                  venceTxt = dtFmt.format(last);
                } else {
                  final last = fi.add(Duration(days: 15 * numCuotas));
                  venceTxt = dtFmt.format(last);
                }
              } catch (_) {
                venceTxt = '-';
              }

              final tasaTxt = (it.tasaInteres).toString();

              return InkWell(
                onTap: null, // detalle deshabilitado por ahora
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nombre.isEmpty ? 'Cliente' : nombre,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          // Un solo botón Editar (para cualquier préstamo NO pagado)
                          if ((estado ?? '') != 'PAGADO')
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => LoanEditPage(prestamoId: it.id)),
                                );
                                if (result == true && mounted) {
                                  setState(() => _future = _load());
                                }
                              },
                            ),
                          LoanStatusBadge(estado: estado),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Código: $codigo',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vence: $venceTxt${tasaTxt.isEmpty ? '' : '   •   Tasa: $tasaTxt%'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('Monto: ', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(moneyFmt.format(monto)), // $ delante
                          const Spacer(),
                          Text('Cuotas: $numCuotas', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewChooser(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
