import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'client_model.dart';
import 'client_service.dart';
import 'package:dio/dio.dart';

final _buscarProvider = StateProvider<String>((ref) => '');
final _clientesFutureProvider = FutureProvider.autoDispose<ClientesResp>((ref) async {
  final svc = ref.read(clientesServiceProvider);
  final query = ref.watch(_buscarProvider);
  return svc.listar(buscar: query.isEmpty ? null : query);
});

class ClientesPage extends ConsumerStatefulWidget {
  const ClientesPage({super.key});
  @override
  ConsumerState<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends ConsumerState<ClientesPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debouncer;

  @override
  void dispose() { _debouncer?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  void _onSearchChanged(String v) {
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 350), () {
      ref.read(_buscarProvider.notifier).state = v;
    });
  }

  Future<void> _openForm({Cliente? cliente}) async {
    final nombreCtrl = TextEditingController(text: cliente?.nombre ?? '');
    final telCtrl = TextEditingController(text: cliente?.telefono ?? '');
    final formKey = GlobalKey<FormState>();
    final regexNombre = RegExp(r'^[A-Za-zÁÉÍÓÚáéíóúÑñ ]+$');
    final regexTel = RegExp(r'^\d+$');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) { if (v==null||v.trim().isEmpty) return 'Requerido';
                if (!regexNombre.hasMatch(v.trim())) return 'Solo letras y espacios'; return null; },
            ),
            TextFormField(
              controller: telCtrl, decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.number,
              validator: (v) { if (v==null||v.trim().isEmpty) return 'Requerido';
                if (!regexTel.hasMatch(v.trim())) return 'Solo dígitos';
                if (v.trim().length < 7 || v.trim().length > 15) return 'Entre 7 y 15 dígitos'; return null; },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final svc = ref.read(clientesServiceProvider);
                if (cliente == null) {
                  await svc.crear(nombre: nombreCtrl.text, telefono: telCtrl.text);
                } else {
                  await svc.actualizar(id: cliente.id, nombre: nombreCtrl.text, telefono: telCtrl.text);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: Text(cliente == null ? 'Crear' : 'Guardar'),
          ),
        ],
      ),
    );

    if (saved == true) ref.invalidate(_clientesFutureProvider);
  }

  Future<void> _showDetalle(int id) async {
    try {
      final c = await ref.read(clientesServiceProvider).getById(id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Detalle del cliente'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Código: ${c.codigo}'),
            Text('Nombre: ${c.nombre}'),
            Text('Teléfono: ${c.telefono}'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _confirmEliminar(Cliente c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text('¿Eliminar "${c.codigo} — ${c.nombre}"?\n'
            'Si tiene préstamos, se bloqueará (operación protegida en paso 4).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(clientesServiceProvider).eliminar(c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
      ref.invalidate(_clientesFutureProvider);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
      final msg = (code == 409 && detail != null)
          ? 'No se puede eliminar: $detail'
          : 'Error al eliminar (HTTP $code)';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listaAsync = ref.watch(_clientesFutureProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar (código, nombre o teléfono)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _onSearchChanged(''); })
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: listaAsync.when(
              data: (resp) => resp.items.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.separated(
                      itemCount: resp.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final c = resp.items[i];
                        return ListTile(
                          title: Text('${c.codigo} — ${c.nombre}'),
                          subtitle: Text('Tel: ${c.telefono}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'detalle') _showDetalle(c.id);
                              if (v == 'editar') _openForm(cliente: c);
                              if (v == 'eliminar') _confirmEliminar(c);
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(value: 'detalle', child: Text('Ver detalle')),
                              PopupMenuItem(value: 'editar', child: Text('Editar')),
                              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                            ],
                          ),
                          onTap: () => _showDetalle(c.id),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
