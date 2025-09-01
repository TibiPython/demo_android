// lib/features/prestamos/ui/loan_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../loan_service.dart';

class LoanDetailPage extends ConsumerStatefulWidget {
  final int id;
  const LoanDetailPage({super.key, required this.id});

  @override
  ConsumerState<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends ConsumerState<LoanDetailPage>
    with WidgetsBindingObserver {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    debugPrint('Cargando LoanDetailPage: UI ✅'); // comprobar en consola
    WidgetsBinding.instance.addObserver(this);
    _future = _fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final api = ref.read(prestamosApiProvider);
    final res = await api.getResumenByPrestamoId(widget.id); // usa RESUMEN
    return Map<String, dynamic>.from(res);
  }

  Future<void> _reload() async {
    setState(() => _future = _fetch());
    await _future;
  }

  Widget _estadoPill(String estado) {
    final e = estado.toUpperCase();
    Color bg, fg;
    switch (e) {
      case 'PAGADO':
        bg = const Color(0xFFE0E7FF); fg = const Color(0xFF4338CA);
        break;
      case 'VENCIDO':
        bg = const Color(0xFFFEE2E2); fg = const Color(0xFFB91C1C);
        break;
      default:
        bg = const Color(0xFFFFF7ED); fg = const Color(0xFF9A3412);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: fg.withOpacity(0.25))),
      child: Text(estado, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _kv(String k, String v) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$k: ', style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: Text(v)),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del préstamo')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final data = snap.data ?? const <String, dynamic>{};
          final resumen = (data['resumen'] as Map? ?? const {}).cast<String, dynamic>();
          final cuotas = List<Map<String, dynamic>>.from(data['cuotas'] as List? ?? const []);

          final cliente = Map<String, dynamic>.from(resumen['cliente'] as Map? ?? const {});
          final estado = (resumen['estado'] ?? '').toString();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    (cliente['nombre'] ?? '(sin cliente)').toString(),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                _estadoPill(estado),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _kv('Modalidad', (resumen['modalidad'] ?? '').toString()),
                            _kv('Vence', (resumen['vence_ultima_cuota'] ?? '').toString()),
                            _kv('Crédito', (resumen['importe_credito'] ?? '').toString()),
                            _kv('Tasa %', (resumen['tasa_interes'] ?? '').toString()),
                            _kv('Interés total', (resumen['total_interes_a_pagar'] ?? '').toString()),
                            _kv('Abonos capital', (resumen['total_abonos_capital'] ?? '').toString()),
                            _kv('Capital pendiente', (resumen['capital_pendiente'] ?? '').toString()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Cuotas', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...cuotas.map((c) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${c['numero'] ?? c['cuota_numero'] ?? ''}'),
                      ),
                      // ⬇️ "Fecha de pago" (si existe) debajo de "Vence:"
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vence: ${c['fecha_vencimiento'] ?? ''}'),
                          (() {
                            final v = c['fecha_pago'];
                            if (v == null) return const SizedBox.shrink();
                            final s = v.toString();
                            if (s.isEmpty) return const SizedBox.shrink();
                            final out = s.length >= 10 ? s.substring(0, 10) : s;
                            return Text('Fecha de pago: $out', style: Theme.of(context).textTheme.bodySmall);
                          }()),
                        ],
                      ),
                      subtitle: Text(
                        'Interés a pagar: ${c['interes_a_pagar'] ?? ''}  •  Pagado: ${c['interes_pagado'] ?? ''}',
                      ),
                      trailing: Text((c['estado'] ?? '').toString()),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
