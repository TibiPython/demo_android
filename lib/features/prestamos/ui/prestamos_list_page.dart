import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import 'package:demo_android/core/http.dart';
import 'package:demo_android/features/cuotas/cuotas_service.dart';

import 'package:demo_android/features/prestamos/ui/loan_new_page.dart';
import 'package:demo_android/features/prestamos/ui/loan_new_manual_page.dart';

// ⬇️ NUEVO: bus de refresh
import 'package:demo_android/features/prestamos/refresh_bus.dart';

// -------- Estilos chip de estado --------
class _EstadoStyle {
  final Color bg;
  final Color fg;
  final String label;
  const _EstadoStyle(this.bg, this.fg, this.label);
}

_EstadoStyle _styleParaEstado(BuildContext ctx, String? estadoRaw) {
  final e = (estadoRaw ?? 'PENDIENTE').trim().toUpperCase();
  switch (e) {
    case 'PAGADO':
      return _EstadoStyle(Colors.green.withOpacity(0.12), Colors.green.shade800, 'Pagado');
    case 'VENCIDO':
      return _EstadoStyle(Colors.red.withOpacity(0.12), Colors.red.shade800, 'Vencido');
    default:
      return _EstadoStyle(Colors.orange.withOpacity(0.12), Colors.orange.shade800, 'Pendiente');
  }
}

// -------- Modelos locales --------
class _LoanItem {
  final int id;
  final String codCli;
  final String? clienteNombre;
  final double monto;
  final double tasaInteres;
  final String modalidad;
  final String fechaCredito; // yyyy-MM-dd
  final String estado;
  final String folio;

  // Del propio /prestamos (si llegan)
  final int? numCuotas;
  final int? cuotasTotal;
  final int? cuotasPagadas;
  final int? cuotasPendientes;
  final String? fechaVencimiento; // si viene directo del backend

  _LoanItem({
    required this.id,
    required this.codCli,
    required this.clienteNombre,
    required this.monto,
    required this.tasaInteres,
    required this.modalidad,
    required this.fechaCredito,
    required this.estado,
    required this.folio,
    this.numCuotas,
    this.cuotasTotal,
    this.cuotasPagadas,
    this.cuotasPendientes,
    this.fechaVencimiento,
  });

  factory _LoanItem.fromJson(Map<String, dynamic> j) {
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    double _asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    String? _pickStr(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
      return null;
    }

    int? _pickInt(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null) return n;
      }
      return null;
    }

    final cliente = (j['cliente'] is Map) ? (j['cliente'] as Map) : null;

    final id = _asInt(j['id']);
    final folioBackend = _pickStr(j, ['folio', 'id_folio', 'folio_id', 'folioId', 'idFolio']);
    final folio = folioBackend ?? 'P-${id.toString().padLeft(4, '0')}';

    return _LoanItem(
      id: id,
      codCli: (j['cod_cli'] ?? j['codigo'] ?? '').toString(),
      clienteNombre: cliente?['nombre']?.toString(),
      monto: _asDouble(j['importe_credito'] ?? j['monto'] ?? 0),
      tasaInteres: _asDouble(j['tasa_interes'] ?? j['tasa'] ?? 0),
      modalidad: (j['modalidad'] ?? '').toString(),
      fechaCredito: (j['fecha_credito'] ?? j['fecha_inicio'] ?? '').toString(),
      estado: (j['estado'] ?? 'PENDIENTE').toString(),
      folio: folio,
      numCuotas: _pickInt(j, ['num_cuotas', 'n_cuotas', 'cuotas']),
      cuotasTotal: _pickInt(j, ['cuotas_total', 'total_cuotas', 'n_cuotas', 'num_cuotas', 'cuotas']),
      cuotasPagadas: _pickInt(j, ['cuotas_pagadas', 'pagadas', 'n_cuotas_pagadas', 'paid_installments']),
      cuotasPendientes: _pickInt(j, ['cuotas_pendientes', 'pendientes', 'n_cuotas_pendientes', 'pending_installments']),
      fechaVencimiento: _pickStr(j, ['fecha_vencimiento', 'vence', 'fecha_fin', 'fecha_termino']),
    );
  }
}

// Resumen por préstamo proveniente de CuotasService
class _ResumenLite {
  final DateTime? venceUltimaCuota;
  final int? pagadas;
  final int? pendientes;
  final int? total;
  const _ResumenLite({this.venceUltimaCuota, this.pagadas, this.pendientes, this.total});
}

// -------- Providers --------

// Lista /prestamos
final _prestamosProvider = FutureProvider<List<_LoanItem>>((ref) async {
  final dio = ref.read(dioProvider);
  final Response resp = await dio.get('/prestamos', queryParameters: {'page': 1, 'page_size': 200});
  final data = resp.data;
  final items = (data is Map && data['items'] is List) ? (data['items'] as List) : const [];
  return items.map((e) => _LoanItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

// Resumen masivo desde CuotasService (Vence directo si existe)
final _resumenMasivoProvider = FutureProvider<Map<int, _ResumenLite>>((ref) async {
  final svc = ref.read(cuotasServiceProvider);
  try {
    final list = await svc.listarResumenPrestamos();
    final map = <int, _ResumenLite>{};
    for (final r in list) {
      map[r.id] = _ResumenLite(venceUltimaCuota: r.venceUltimaCuota);
    }
    return map;
  } catch (_) {
    return <int, _ResumenLite>{};
  }
});

// Carga perezosa por ítem: si faltan contadores o falta "Vence", se usa obtenerResumenDePrestamo(id)
final _contadoresProvider = FutureProvider.family<_ResumenLite, int>((ref, prestamoId) async {
  final svc = ref.read(cuotasServiceProvider);
  try {
    final raw = await svc.obtenerResumenDePrestamo(prestamoId);
    final cuotas = (raw['cuotas'] as List?) ?? const [];
    int pag = 0;
    int pend = 0;
    for (final c in cuotas) {
      final m = (c as Map).cast<String, dynamic>();
      final estado = (m['estado'] ?? '').toString().toUpperCase();
      if (estado == 'PAGADO') {
        pag++;
      } else {
        pend++;
      }
    }
    DateTime? vence;
    try {
      final resumen = (raw['resumen'] as Map?)?.cast<String, dynamic>() ?? {};
      final v = resumen['vence_ultima_cuota'];
      if (v != null && v.toString().isNotEmpty) {
        vence = DateTime.tryParse(v.toString());
      }
    } catch (_) {}
    if (vence == null) {
      for (final c in cuotas) {
        final m = (c as Map).cast<String, dynamic>();
        final fv = m['fecha_vencimiento']?.toString();
        final d = fv == null ? null : DateTime.tryParse(fv);
        if (d != null && (vence == null || d.isAfter(vence))) {
          vence = d;
        }
      }
    }
    return _ResumenLite(venceUltimaCuota: vence, pagadas: pag, pendientes: pend, total: pag + pend);
  } catch (_) {
    return const _ResumenLite();
  }
});

// Estados canónicos desde backend (con fallback a /cuotas)
final _estadosByIdsProvider = FutureProvider.family<Map<int, String>, List<int>>((ref, ids) async {
  final dio = ref.read(dioProvider);
  if (ids.isEmpty) return const <int, String>{};
  final idsParam = ids.join(',');
  try {
    final resp = await dio.get('/prestamos/estado', queryParameters: {'ids': idsParam});
    final data = resp.data;
    if (data is List) {
      final map = <int, String>{};
      for (final e in data) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final id = (m['id'] is num) ? (m['id'] as num).toInt() : int.tryParse('${m['id']}');
          final est = (m['estado'] ?? '').toString();
          if (id != null && est.isNotEmpty) map[id] = est;
        }
      }
      return map;
    }
    return const <int, String>{};
  } on DioException {
    try {
      final resp = await dio.get('/cuotas/estado/resumen-prestamos', queryParameters: {'ids': idsParam});
      final data = resp.data;
      if (data is List) {
        final map = <int, String>{};
        for (final e in data) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final id = (m['id'] is num) ? (m['id'] as num).toInt() : int.tryParse('${m['id']}');
            final est = (m['estado'] ?? '').toString();
            if (id != null && est.isNotEmpty) map[id] = est;
          }
        }
        return map;
      }
      return const <int, String>{};
    } on DioException {
      return const <int, String>{};
    }
  }
});

// -------- Utilidades de fecha --------
DateTime? _tryParseIso(String s) {
  if (s.isEmpty) return null;
  try {
    return DateTime.tryParse(s);
  } catch (_) {
    return null;
  }
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _addMonths(DateTime dt, int months) {
  final y = dt.year + ((dt.month - 1 + months) ~/ 12);
  final m = ((dt.month - 1 + months) % 12) + 1;
  final d = dt.day;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d > lastDay ? lastDay : d);
}

String? _venceEstimado(_LoanItem it) {
  final inicio = _tryParseIso(it.fechaCredito);
  if (inicio == null) return null;
  final n = it.numCuotas ?? it.cuotasTotal ?? 0;
  if (n <= 0) return null;
  final pasos = (n - 1).clamp(0, 10000);
  final mod = it.modalidad.trim().toLowerCase();
  if (mod.contains('quincen')) {
    return _fmtDate(inicio.add(Duration(days: 15 * pasos)));
  }
  return _fmtDate(_addMonths(inicio, pasos));
}

// -------- Página --------
class PrestamosListPage extends ConsumerWidget {
  const PrestamosListPage({super.key});

  Future<void> _openNewLoanSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_mode),
                  title: const Text('Préstamo automático'),
                  subtitle: const Text('Genera el plan automáticamente según tasa y cuotas'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => LoanNewPage()),
                    );
                    if (created == true) {
                      ref.invalidate(_prestamosProvider);
                      ref.invalidate(_resumenMasivoProvider);
                    }
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Préstamo manual'),
                  subtitle: const Text('Ingresas el plan manualmente (capital/interés por cuota)'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const LoanNewManualPage()),
                    );
                    if (created == true) {
                      ref.invalidate(_prestamosProvider);
                      ref.invalidate(_resumenMasivoProvider);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _externalRefresh(WidgetRef ref) async {
    ref.invalidate(_prestamosProvider);
    ref.invalidate(_resumenMasivoProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⬇️ NUEVO: escuchamos el “bus” para refrescar automáticamente
    ref.listen<int>(prestamosRefreshTickProvider, (prev, next) {
      if (prev == null || next != prev) {
        _externalRefresh(ref);
      }
    });

    final loansAsync = ref.watch(_prestamosProvider);
    final resumenMasivoAsync = ref.watch(_resumenMasivoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Préstamos'),
        actions: [
          IconButton(
            tooltip: 'Nuevo préstamo',
            icon: const Icon(Icons.add),
            onPressed: () => _openNewLoanSheet(context, ref),
          ),
        ],
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView('Error al cargar préstamos:\n$e'),
        data: (loans) {
          final resumenMasivo = resumenMasivoAsync.maybeWhen(
            data: (m) => m,
            orElse: () => const <int, _ResumenLite>{},
          );
          
final ids = loans.map((e) => e.id).toList(growable: false);
final estadosAsync = ref.watch(_estadosByIdsProvider(ids));
final estados = estadosAsync.maybeWhen(
  data: (m) => m,
  orElse: () => const <int, String>{},
);
return RefreshIndicator(
            onRefresh: () => _externalRefresh(ref),
            child: _ListView(loans: loans, resumenMasivo: resumenMasivo, estados: estados),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nuevo préstamo',
        onPressed: () => _openNewLoanSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String msg;
  const _ErrorView(this.msg);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(msg, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ListView extends ConsumerWidget {
  final List<_LoanItem> loans;
  final Map<int, _ResumenLite> resumenMasivo;
  final Map<int, String> estados;
  const _ListView({required this.loans, required this.resumenMasivo, this.estados = const <int, String>{}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loans.isEmpty) {
      return ListView(
        children: const [SizedBox(height: 240), Center(child: Text('Sin préstamos')), SizedBox(height: 240)],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: loans.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final it = loans[i];
        final estadoCanonico = estados[it.id];
        final estBackend = _styleParaEstado(ctx, estadoCanonico ?? it.estado);

        int? total = it.cuotasTotal ?? it.numCuotas;
        int? pag = it.cuotasPagadas;
        int? pen = it.cuotasPendientes;
        String? venceStr = it.fechaVencimiento;

        final rm = resumenMasivo[it.id];
        if (rm?.venceUltimaCuota != null) {
          venceStr = _fmtDate(rm!.venceUltimaCuota!);
        }

        final needCounts = (pag == null && pen == null);
        final needVence = (venceStr == null);
        if (needCounts || needVence) {
          final countsAsync = ref.watch(_contadoresProvider(it.id));
          countsAsync.whenData((c) {
            total ??= c.total;
            pag ??= c.pagadas;
            pen ??= c.pendientes;
            if (venceStr == null && c.venceUltimaCuota != null) {
              venceStr = _fmtDate(c.venceUltimaCuota!);
            }
          });
        }

        if (total != null) {
          if (pag == null && pen != null) pag = (total! - pen!).clamp(0, total!);
          if (pen == null && pag != null) pen = (total! - pag!).clamp(0, total!);
        }

        // Estado visible derivado opcional (solo UI). Si no lo quieres, usa siempre estBackend.
        String estadoVisible = estadoCanonico ?? it.estado;
        if (total != null && total! > 0 && pag != null && pag! >= total!) {
          estadoVisible = 'PAGADO';
        }
        final est = _styleParaEstado(ctx, estadoVisible);

        final titulo = '${it.clienteNombre ?? it.codCli} — ${it.folio}';
        final linea1 = Text('Monto: ${it.monto.toStringAsFixed(2)} • Tasa: ${it.tasaInteres}%');

        Widget? linea2;
        if (pag != null || pen != null) {
          final p1 = (pag != null) ? 'Pagadas: $pag' : null;
          final p2 = (pen != null) ? 'Por pagar: $pen' : null;
          final l2 = [p1, p2].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
          if (l2.isNotEmpty) linea2 = Text(l2);
        }

        final inicioStr = it.fechaCredito.isNotEmpty ? 'Inicio: ${it.fechaCredito}' : null;
        final venceFinal = venceStr ?? _venceEstimado(it);
        final venceLine = (venceFinal != null && venceFinal.isNotEmpty) ? 'Vence: $venceFinal' : null;
        final l3 = [inicioStr, venceLine].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
        final linea3 = l3.isEmpty ? null : Text(l3);

        final estadoChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: est.bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: est.fg.withOpacity(0.35)),
          ),
          child: Text(est.label, style: TextStyle(color: est.fg, fontWeight: FontWeight.w600)),
        );

        return ListTile(
          title: Text(titulo),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              linea1,
              if (linea2 != null) linea2,
              if (linea3 != null) linea3,
            ],
          ),
          trailing: estadoChip,
          isThreeLine: true,
          onTap: () async {
            await Navigator.of(ctx).pushNamed('/prestamos/detalle', arguments: {'id': it.id});
            // Refresco al volver desde detalle abierto aquí:
            ref.invalidate(_prestamosProvider);
            ref.invalidate(_resumenMasivoProvider);
          },
        );
      },
    );
  }
}
