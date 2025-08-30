import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../loan_service.dart';

class PrestamosListPage extends ConsumerWidget {
  const PrestamosListPage({super.key});

  Future<List<Map<String, dynamic>>> _fetch(WidgetRef ref) async {
    final api = ref.read(prestamosApiProvider);
    final page = await api.list(page: 1, pageSize: 20);
    return List<Map<String, dynamic>>.from(page['items']);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préstamos')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetch(ref),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return const Center(child: Text('Sin préstamos'));

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = items[i];
              final id = p['id'] as int;
              final cliente = p['cliente'] as Map?;
              final clienteNom = (cliente?['nombre'] ?? '(sin cliente)').toString();
              final monto = p['monto'];
              final cuotas = p['num_cuotas'];

              return ListTile(
                leading: const Icon(Icons.request_page),
                title: Text(clienteNom),
                subtitle: Text('Monto: $monto  •  Cuotas: $cuotas'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/prestamos/$id'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/prestamos/nuevo'), // 👈 GoRouter
        child: const Icon(Icons.add),
      ),
    );
  }
}
