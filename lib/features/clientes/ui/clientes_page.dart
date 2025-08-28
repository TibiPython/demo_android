import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/http.dart'; // <- dioProvider
import 'client_form_page.dart';   // <- NUEVO

class ClientesPage extends ConsumerStatefulWidget {
  const ClientesPage({super.key});

  @override
  ConsumerState<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends ConsumerState<ClientesPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final dio = ref.read(dioProvider);
    final resp = await dio.get('/clientes', queryParameters: {
      'page': 1,
      'page_size': 50,
    });
    final data = resp.data as Map;
    final items = List<Map<String, dynamic>>.from(data['items']);
    return items;
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  Future<void> _goToCreateClient() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClientFormPage()),
    );
    if (created == true) {
      _reload(); // <- refresca la lista al volver
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('Sin clientes'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = items[i];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(c['nombre'] ?? ''),
                  subtitle: Text(
                    'Código: ${c['codigo'] ?? '-'}  •  Tel: ${c['telefono'] ?? '-'}',
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToCreateClient,
        tooltip: 'Nuevo cliente',
        child: const Icon(Icons.add),
      ),
    );
  }
}
