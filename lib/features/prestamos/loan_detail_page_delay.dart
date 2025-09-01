import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/http.dart';                 // dioProvider
import 'loan_model.dart';                   // Prestamo
import 'ui/status_theme.dart';              // LoanTintedSection + LoanStatusBadge

class LoanDetailPage extends ConsumerWidget {
  final int id;
  const LoanDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = ref.watch(dioProvider);
    final fmt = NumberFormat.currency(locale: 'es_CO', symbol: r'$');

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del préstamo')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetch(dio, id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data ?? const <String, dynamic>{};
          final p = Prestamo.fromJson(data);

          final clienteNombre = (p.cliente['nombre'] ?? '').toString();
          final clienteCodigo = (p.cliente['codigo'] ?? '').toString();
          final estado = p.estado;

          final header = LoanTintedSection(
            estado: estado,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        clienteNombre.isEmpty ? 'Cliente' : clienteNombre,
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
                  'Código: $clienteCodigo',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withOpacity(0.6),
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fmt.format(p.monto),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Text(
                      p.modalidad,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          );

          return ListView(
            children: [
              header,
              _infoTile('Fecha inicio', _fmtDate(p.fechaInicio)),
              _infoTile('Cuotas', p.numCuotas.toString()),
              _infoTile('Tasa interés', '${p.tasaInteres.toStringAsFixed(2)} %'),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Cuotas', style: Theme.of(context).textTheme.titleMedium),
              ),
              ...p.cuotas.map((c) {
                final venceStr = _fmtAnyDate(c.fechaVencimiento);
                final fechaPagoStr = _fechaPagoStr(c);

                return ListTile(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vence: $venceStr'),
                      if (fechaPagoStr != null)
                        Text(
                          'Fecha de pago: $fechaPagoStr',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  subtitle: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Monto pagado: ${fmt.format(c.interesPagado)}'),
                      const Text('·'),
                      const Text('Estado:'),
                    ],
                  ),
                  trailing: Text(
                    c.estado,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: LoanStatusTheme.of(context, c.estado).fg,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _fetch(dio, int id) async {
    final res = await dio.get('/prestamos/$id');
    return (res.data as Map).cast<String, dynamic>();
  }

  String _fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

  String _fmtAnyDate(dynamic v) {
    if (v is DateTime) return _fmtDate(v);
    if (v is String) {
      if (v.length >= 10) return v.substring(0, 10);
      final p = DateTime.tryParse(v);
      if (p != null) return _fmtDate(p);
      return v;
    }
    if (v is int) {
      try {
        return _fmtDate(DateTime.fromMillisecondsSinceEpoch(v));
      } catch (_) {}
    }
    return '-';
  }

  String? _fechaPagoStr(dynamic cuota) {
    dynamic fp;
    try {
      // ignore: avoid_dynamic_calls
      fp = cuota.fechaPago;
    } catch (_) {}
    if (fp == null && cuota is Map) {
      fp = cuota['fecha_pago'] ?? cuota['fechaPago'];
    }
    if (fp == null) return null;

    if (fp is DateTime) return _fmtDate(fp);
    if (fp is String && fp.isNotEmpty) {
      if (fp.length >= 10) return fp.substring(0, 10);
      final p = DateTime.tryParse(fp);
      return p != null ? _fmtDate(p) : fp;
    }
    if (fp is int) {
      try {
        return _fmtDate(DateTime.fromMillisecondsSinceEpoch(fp));
      } catch (_) {}
    }
    return null;
  }

  Widget _infoTile(String k, String v) => ListTile(
        dense: true,
        title: Text(k),
        trailing: Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}
