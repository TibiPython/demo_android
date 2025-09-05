// Pantalla principal de la lista de Préstamos (se importa desde main.dart).
// Nota: aquí se muestra cada préstamo con Nombre, Estado, Código, Monto, Modalidad,
// y la línea extra "Vence: …   •   Tasa: …%". Además se añadió "No. de cuotas".
// El tap sobre un préstamo NO navega al detalle (detalle deshabilitado).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/http.dart';
import '../loan_model.dart';
import '../loan_new_page.dart';
import 'status_theme.dart';

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

  Future<void> _openNew(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoanNewPage()),
    );
    if (result == true && mounted) {
      setState(() => _future = _load()); // refrescar al volver
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_CO', symbol: r'$');

String _pf(num? v) {
  if (v == null) return '-';
  final s = NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 2).format(v);
  return '\$\u00A0' + s;
}


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
              final estado = it.estado; // viene del backend
              final nombre = (it.cliente['nombre'] ?? '').toString();
              final codigo = (it.cliente['codigo'] ?? '').toString();
              final folio = 'P-${it.id.toString().padLeft(4, '0')}';
              final monto = it.monto;

              // Calcular "Vence" (última cuota) a partir de fechaInicio + numCuotas y modalidad
              final dtFmt = DateFormat('yyyy-MM-dd');
              String venceTxt = '-';
              final int numCuotas = (it.numCuotas ?? 0) as int; // <-- No. de cuotas
              try {
                final fiStr = (it.fechaInicio ?? '').toString();
                if (fiStr.isNotEmpty) {
                  final fi = DateTime.parse(fiStr);
                  final mod = (it.modalidad ?? '').toString().toLowerCase();
                  if (numCuotas > 0) {
                    if (mod.startsWith('men')) {
                      final v = DateTime(fi.year, fi.month + numCuotas, fi.day);
                      venceTxt = dtFmt.format(v);
                    } else {
                      final v = fi.add(Duration(days: 15 * numCuotas));
                      venceTxt = dtFmt.format(v);
                    }
                  }
                }
              } catch (_) {}

              // Tasa % (solo si es numérico para evitar errores de tipo)
              final String tasaTxt = (() {
                final t = it.tasaInteres;
                if (t == null) return '';
                if (t is num) return t.toStringAsFixed(2);
                return ''; // ignorar otros tipos
              })();

              // SIN navegación al detalle (no onTap)
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: LoanTintedSection(
                  estado: estado,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          LoanStatusBadge(estado: estado),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Folio: $folio',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 4),
                      // Línea con Vence y Tasa (lo demás queda igual)
                      Text(
                        'Vence: $venceTxt${tasaTxt.isEmpty ? '' : '   •   Tasa: $tasaTxt%'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 4),
                      // NUEVO: No. de cuotas (línea aparte, mismo estilo)
                      Text(
                        'No. de cuotas: $numCuotas',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pf(monto),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          if ((it.modalidad).isNotEmpty)
                            Text(it.modalidad, style: Theme.of(context).textTheme.titleSmall),
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
        onPressed: () => _openNew(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}