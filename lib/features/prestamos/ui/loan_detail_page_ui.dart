import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../loan_service.dart';

class LoanDetailPageUI extends ConsumerStatefulWidget {
  final int id;
  const LoanDetailPageUI({super.key, required this.id});

  @override
  ConsumerState<LoanDetailPageUI> createState() => _LoanDetailPageUIState();
}


String _moneyLeading(String? v) {
  final raw = (v ?? '').trim();
  if (raw.isEmpty) return '';
  // si termina en '$' -> moverlo delante
  final m = RegExp(r'^(.*?)(?:\s*\$)$').firstMatch(raw);
  if (m != null) {
    final body = m.group(1)!.trim();
    return r'$ ' + body;
  }
  // si ya empieza con '$' o no tiene símbolo, dejar igual
  return raw;
}
class _LoanDetailPageUIState extends ConsumerState<LoanDetailPageUI>
    with WidgetsBindingObserver {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
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

  // ---------- helpers ----------
  String _firstNonEmpty(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  /// Intenta obtener el nombre del cliente desde varias formas:
  /// - resumen['cliente']['nombre']
  /// - resumen['cliente_nombre'] / 'nombre_cliente' / 'clienteNombre'
  String _clienteNombre(Map<String, dynamic> resumen) {
    final cli = resumen['cliente'];
    if (cli is Map<String, dynamic>) {
      final n = _firstNonEmpty(cli, ['nombre', 'name']);
      if (n.isNotEmpty) return n;
    }
    final n = _firstNonEmpty(
      resumen,
      ['cliente_nombre', 'nombre_cliente', 'clienteNombre'],
    );
    return n;
  }

  /// Similar para el código del cliente.
  String _clienteCodigo(Map<String, dynamic> resumen) {
    final cli = resumen['cliente'];
    if (cli is Map<String, dynamic>) {
      final c = _firstNonEmpty(cli, ['codigo', 'code']);
      if (c.isNotEmpty) return c;
    }
    final c = _firstNonEmpty(
      resumen,
      ['cliente_codigo', 'codigo_cliente', 'clienteCodigo'],
    );
    return c;
  }

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
          final resumen = (data['resumen'] as Map? ?? const {})
              .cast<String, dynamic>();
          final cuotas = List<Map<String, dynamic>>.from(
              data['cuotas'] as List? ?? const []);

          final nombreCliente = _clienteNombre(resumen);
          final codigoCliente = _clienteCodigo(resumen);
          final estado = (resumen['estado'] ?? '').toString();
          final modalidad = (resumen['modalidad'] ?? '').toString();
          final venceUltima =
              (resumen['vence_ultima_cuota'] ?? '').toString();
          final credito = _moneyLeading((resumen['importe_credito'] ?? '').toString());
          final tasa = (resumen['tasa_interes'] ?? '').toString();

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
                              children: [
                                Expanded(
                                  child: Text(
                                    // 👇 ya no muestra "(sin cliente)"
                                    nombreCliente.isEmpty
                                        ? 'Cliente'
                                        : nombreCliente,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _pill(estado),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (codigoCliente.isNotEmpty)
                              _kv('Código', codigoCliente),
                            if (modalidad.isNotEmpty)
                              _kv('Modalidad', modalidad),
                            if (venceUltima.isNotEmpty)
                              _kv('Vence', venceUltima),
                            if (credito.isNotEmpty) _kv('Crédito', credito),
                            if (tasa.isNotEmpty) _kv('Tasa %', tasa),
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
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vence: ${c['fecha_vencimiento'] ?? ''}'),
                          (() {
                            final v = c['fecha_pago'];
                            if (v == null) return const SizedBox.shrink();
                            final s = v.toString();
                            if (s.isEmpty) return const SizedBox.shrink();
                            final out =
                                s.length >= 10 ? s.substring(0, 10) : s;
                            return Text(
                              'Fecha de pago: $out',
                              style: Theme.of(context).textTheme.bodySmall,
                            );
                          }()),
                        ],
                      ),
                      subtitle: Text(
                        'Interés a pagar: ${_moneyLeading(c['interes_a_pagar']?.toString())}  •  Pagado: ${_moneyLeading(c["interes_pagado"]?.toString())}',
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

  Widget _pill(String estado) {
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
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(estado,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$k: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
