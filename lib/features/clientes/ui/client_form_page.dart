
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:demo_android/core/http.dart'; // dioProvider
import 'package:demo_android/core/safe_close.dart'; // cierre híbrido

class ClientFormPage extends ConsumerStatefulWidget {
  const ClientFormPage({super.key});

  @override
  ConsumerState<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends ConsumerState<ClientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _identCtrl  = TextEditingController();
  final _dirCtrl    = TextEditingController();
  final _telCtrl    = TextEditingController();
  final _emailCtrl  = TextEditingController();
  bool _saving = false;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final payload = <String, dynamic>{
        // NO enviar 'codigo': backend lo asigna
        'nombre': _nombreCtrl.text.trim(),
        'identificacion': _identCtrl.text.trim(),
        'direccion': _dirCtrl.text.trim(),
        'telefono': _telCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

      await dio.post('/clientes', data: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado')),
      );
      await SafeClose.pop(context, true); // cierre híbrido
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Padding(
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
                    hintText: 'Se asigna al guardar',
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
                  validator: _req, // requerido pero sin restricción de formato
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
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Guardando...' : 'Guardar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
