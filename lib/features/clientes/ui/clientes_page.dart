import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/http.dart'; // dioProvider
import 'client_form_page.dart';
import 'client_edit_page.dart';

class ClientesPage extends ConsumerStatefulWidget {
  const ClientesPage({super.key});

  @override
  ConsumerState<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends ConsumerState<ClientesPage> {
  late Future<List<Map<String, dynamic>>> _future;

  Future<List<Map<String, dynamic>>> _fetch() async {
    final dio = ref.read(dioProvider);
    final resp = await dio.get('/clientes');
    final data = resp.data;
    if (data is List) return List<Map<String, dynamic>>.from(data);
    if (data is Map && data['items'] is List) return List<Map<String, dynamic>>.from(data['items']);
    return const [];
  }

  Future<void> _reload() async {
    setState(() => _future = _fetch());
    await _future;
  }

  void _goToCreateClient() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFormPage()));
    if (mounted) _reload();
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  // --- FICHA RÁPIDA + botón Editar ---
  void _showClienteDetalleSheet(int id, String titleLine) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final dio = ref.read(dioProvider);
        final fut = dio.get('/clientes/$id/detalle'); // endpoint de detalle

        Widget _row(String k, String? v, {IconData? icon}) {
          if (v == null || v.trim().isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 2),
                    child: Icon(icon, size: 18),
                  ),
                Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                Expanded(child: Text(v)),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            top: 8,
          ),
          child: FutureBuilder<dynamic>(
            future: fut,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error al cargar detalle: ${snap.error}'),
                );
              }
              final m = Map<String, dynamic>.from(snap.data?.data ?? {});

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabecera
                    Text(titleLine, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Campos (solo si existen)
                    _row('Identificación', (m['identificacion'] ?? '').toString(), icon: Icons.badge),
                    _row('Dirección', (m['direccion'] ?? '').toString(), icon: Icons.home),
                    _row('Email', (m['email'] ?? '').toString(), icon: Icons.email),
                    _row('Teléfono', (m['telefono'] ?? '').toString(), icon: Icons.phone),

                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () async {
                          // Cierra el sheet antes de navegar
                          Navigator.pop(context);
                          final changed = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ClientEditPage(id: id)),
                          );
                          if (changed == true && mounted) {
                            _reload(); // refresca la lista tras editar
                          }
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
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
          if (items.isEmpty) return const Center(child: Text('Sin clientes'));

          // (opcional) ordenar por código numérico ascendente
          items.sort((a, b) {
            final sa = (a['codigo'] ?? a['cod_cli'] ?? '').toString();
            final sb = (b['codigo'] ?? b['cod_cli'] ?? '').toString();
            final da = RegExp(r'\d+').firstMatch(sa)?.group(0) ?? '0';
            final db = RegExp(r'\d+').firstMatch(sb)?.group(0) ?? '0';
            return (int.tryParse(da) ?? 0).compareTo(int.tryParse(db) ?? 0);
          });

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = items[i];
                final id = (c['id'] ?? 0) as int;
                final nombre = (c['nombre'] ?? '').toString();
                final codigo = (c['codigo'] ?? c['cod_cli'] ?? '').toString();
                final telefono = (c['telefono'] ?? '').toString();

                final titleLine = nombre.isEmpty
                    ? '(sin nombre)'
                    : '$nombre  —  Cod. ${codigo.isEmpty ? '---' : codigo}';

                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(titleLine, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: telefono.isEmpty ? null : Text('Teléfono: $telefono'),
                  onTap: () => _showClienteDetalleSheet(id, titleLine), // ficha rápida + Editar
                  trailing: const Icon(Icons.info_outline),
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
