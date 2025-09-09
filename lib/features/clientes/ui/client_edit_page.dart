
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:demo_android/core/http.dart';
import 'package:demo_android/core/safe_close.dart';

class ClientEditPage extends ConsumerStatefulWidget {
  final int id;
  const ClientEditPage({super.key, required this.id});

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

  bool _saving = false;
  bool _loading = true;
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

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  // Nombre: sólo letras (incluye acentos) y espacios; requerido
  String? _nombre(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    final ok = RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]+$').hasMatch(s);
    return ok ? null : 'Sólo letras y espacios';
  }

  // Identificación: sólo enteros; requerido
  String? _ident(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    return RegExp(r'^\d+$').hasMatch(s) ? null : 'Sólo números enteros';
  }

  // Teléfono: sólo enteros; requerido
  String? _tel(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    return RegExp(r'^\d+$').hasMatch(s) ? null : 'Sólo números enteros';
  }

  // Email: requerido + formato básico
  String? _email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'Email inválido';
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/clientes/${widget.id}');
      final data = resp.data;
      final Map<dynamic, dynamic> root = (data is Map) ? data as Map : <dynamic, dynamic>{};
      final dynamic c0 = root['cliente'] ?? root;
      if (c0 is Map) {
        _codigoCtrl.text = (c0['codigo'] ?? '').toString();
        _nombreCtrl.text = (c0['nombre'] ?? '').toString();
        _identCtrl.text  = (c0['identificacion'] ?? '').toString();
        _dirCtrl.text    = (c0['direccion'] ?? '').toString();
        _telCtrl.text    = (c0['telefono'] ?? '').toString();
        _emailCtrl.text  = (c0['email'] ?? '').toString();
      }
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
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
        SnackBar(content: Text('Error al actualizar: $e')),
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
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
                          hintText: 'Asignado por el sistema',
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
                        validator: _nombre,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _identCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Identificación',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: _ident,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dirCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          border: OutlineInputBorder(),
                        ),
                        validator: _req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
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
                        child: ElevatedButton.icon(
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
