// lib/features/cuotas/cuotas_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'cuotas_service.dart';
import 'cuotas_detalle_page.dart';

class CuotasListPage extends ConsumerStatefulWidget {
  const CuotasListPage({super.key});
  @override
  ConsumerState<CuotasListPage> createState() => _CuotasListPageState();
}

class _CuotasListPageState extends ConsumerState<CuotasListPage> {
  late CuotasService service;
  late Future<List<PrestamoResumen>> future;
  final fmtDate = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    service = ref.read(cuotasServiceProvider);
    future = service.listarResumenPrestamos();
  }

  void _reload() {
    setState(() {
      future = service.listarResumenPrestamos();
    });
  }

  Color _estadoColor(String e) {
    switch (e.toUpperCase()) {
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
      appBar: AppBar(title: const Text('Gestor de Cuotas')),
      body: FutureBuilder<List<PrestamoResumen>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('Sin préstamos'));
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              itemCount: data.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = data[i];
                final venceTxt = p.venceUltimaCuota == null
                    ? '-'
                    : fmtDate.format(p.venceUltimaCuota!);
                return ListTile(
                  // leading eliminado para no repetir el ID
                  // leading: CircleAvatar(child: Text(p.id.toString())),
                  title: Text(p.nombreCliente ?? ''),
                  subtitle: Text('VENCE: $venceTxt'),
                  trailing: Chip(
                    label: Text(p.estado),
                    backgroundColor: _estadoColor(p.estado).withOpacity(0.2),
                  ),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => CuotasDetallePage(prestamoId: p.id),
                      ),
                    );
                    if (changed == true) _reload();
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
        label: const Text('Actualizar'),
      ),
    );
  }
}
