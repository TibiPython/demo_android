import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:demo_android/core/api.dart';
import 'package:demo_android/core/safe_close.dart';

class ClientEditPage extends ConsumerStatefulWidget {
  const ClientEditPage({super.key, required this.id});
  final int id;

  @override
  ConsumerState<ClientEditPage> createState() => _ClientEditPageState();
}

class _ClientEditPageState extends ConsumerState<ClientEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _identCtrl  = TextEditingController();
  final _dirCtrl    = TextEditingController();
  final _telCtrl    = TextEditingController();
  final _emailCtrl  = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _identCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/clientes/${widget.id}');
      final j = res.data as Map<String, dynamic>;
      _codigoCtrl.text = (j['codigo'] ?? '').toString();
      _nombreCtrl.text = (j['nombre'] ?? '').toString();
      _identCtrl.text  = (j['identificacion'] ?? '').toString();
      _dirCtrl.text    = (j['direccion'] ?? '').toString();
      _telCtrl.text    = (j['telefono'] ?? '').toString();
      _emailCtrl.text  = (j['email'] ?? '').toString();
    } catch (e) {
      _error = 'Error al cargar: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;
  String? _email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'Email inválido';
  }
  String? _tel(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^\+?\d{6,15}$').hasMatch(s) ? null : 'Teléfono inválido';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final payload = <String, dynamic>{
        'nombre': _nombreCtrl.text.trim(),
        'identificacion': _identCtrl.text.trim(),
        'direccion': _dirCtrl.text.trim(),
        'telefono': _telCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

      await dio.put('/clientes/${widget.id}', data: payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente actualizado')),
      );
      await SafeClose.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _fetch,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      TextFormField(
                        controller: _codigoCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Código',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        validator: _req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _identCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Identificación',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dirCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: _tel,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: _email,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(_saving ? 'Guardando...' : 'Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Editar cliente')),
      body: AbsorbPointer(absorbing: _saving, child: body),
    );
  }
}
