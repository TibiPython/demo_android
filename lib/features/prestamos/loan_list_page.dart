import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'loan_service.dart';
import 'loan_model.dart';

final _codCliProvider = StateProvider<String>((ref) => '');
final _prestamosFutureProvider = FutureProvider.autoDispose<PrestamosResp>((ref) async {
  final svc = ref.read(prestamosServiceProvider);
  final cod = ref.watch(_codCliProvider);
  return svc.listar(codCli: cod.isEmpty ? null : cod);
});

class PrestamosListPage extends ConsumerStatefulWidget {
  const PrestamosListPage({super.key});
  @override
  ConsumerState<PrestamosListPage> createState() => _PrestamosListPageState();
}

class _PrestamosListPageState extends ConsumerState<PrestamosListPage> {
  final _codCtrl = TextEditingController();
  Timer? _debouncer;

  @override
  void dispose() {
    _debouncer?.cancel();
    _codCtrl.dispose();
    super.dispose();
  }

  void _onCodChanged(String v) {
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 350), () {
      ref.read(_codCliProvider.notifier).state = v;
    });
  }

  void _openDetalle(PrestamoItem it) {
    context.push('/prestamos/${it.id}'); // 👈 GoRouter al detalle por id
  }

  @override
  Widget build(BuildContext context) {
    final listaAsync = ref.watch(_prestamosFutureProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Préstamos')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/prestamos/nuevo'), // 👈 GoRouter al “Nuevo”
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _codCtrl,
              decoration: const InputDecoration(
                labelText: 'Filtrar por código de cliente (ej. 001)',
                prefixIcon: Icon(Icons.filter_list),
                border: OutlineInputBorder(),
              ),
              onChanged: _onCodChanged,
            ),
          ),
          Expanded(
            child: listaAsync.when(
              data: (resp) {
                if (resp.items.isEmpty) return const Center(child: Text('Sin préstamos'));
                return ListView.separated(
                  itemCount: resp.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final it = resp.items[i];
                    final cod = it.cliente['codigo'] ?? '';
                    final nom = it.cliente['nombre'] ?? '';
                    return ListTile(
                      title: Text('#${it.id} — $cod — $nom'),
                      subtitle: Text(
                        'Monto: ${it.monto} | ${it.fechaInicio.toString().substring(0,10)} | '
                        'Cuotas: ${it.numCuotas} | Tasa: ${it.tasaInteres}%',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetalle(it),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
