import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/http.dart'; // dioProvider

/// Abre una hoja modal que permite elegir un cliente.
/// Devuelve el 'codigo' seleccionado (ej. "006") o null si se cancela.
Future<String?> showClientPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _ClientPickerSheet(),
  );
}

class _ClientPickerSheet extends ConsumerStatefulWidget {
  const _ClientPickerSheet();

  @override
  ConsumerState<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<_ClientPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/clientes'); // backend existente
      final list = (res.data as List).cast<dynamic>().map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return {
          'id': m['id'],
          'codigo': (m['codigo'] ?? '').toString(),
          'nombre': (m['nombre'] ?? '').toString(),
        };
      }).toList();

      // Mantener solo con código no vacío y ordenar por código numérico
      list.removeWhere((e) => (e['codigo'] as String).trim().isEmpty);
      list.sort((a, b) {
        final ai = int.tryParse((a['codigo'] as String)) ?? 0;
        final bi = int.tryParse((b['codigo'] as String)) ?? 0;
        return ai.compareTo(bi);
      });

      _items = list;
      _filtered = List.of(_items);
    } catch (e) {
      _error = 'Error al cargar clientes: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List.of(_items));
      return;
    }
    setState(() {
      _filtered = _items.where((m) {
        final codigo = (m['codigo'] as String).toLowerCase();
        final nombre = (m['nombre'] as String).toLowerCase();
        return codigo.contains(q) || nombre.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom + 12;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: pad),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar cliente (código o nombre)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('Sin resultados'))
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = _filtered[i];
                            final codigo = m['codigo'] as String;
                            final nombre = m['nombre'] as String;
                            return ListTile(
                              // Lista limpia: sin icono/leading.
                              title: Text(
                                '$codigo - $nombre',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.of(context).pop(codigo),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
