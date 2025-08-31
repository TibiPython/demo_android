import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../../core/http.dart'; // dioProvider

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

  String? _req(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Requerido';
    if (s.length < 2) return 'Mínimo 2 caracteres';
    return null;
  }

  String? _tel(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // opcional
    final ok = RegExp(r'^\+?\d{6,15}\$').hasMatch(s);
    return ok ? null : 'Teléfono inválido';
  }

  String? _email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // opcional
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'Email inválido';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final payload = <String, dynamic>{
        // IMPORTANTE: no enviar 'codigo' — lo asigna el backend automáticamente
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
      Navigator.pop(context, true); // para refrescar la lista al volver
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
                // Código (solo visual; el backend lo autogenera al guardar)
                TextFormField(
                  controller: _codigoCtrl,
                  readOnly: true, // no editable
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    hintText: 'Se asigna al guardar',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Nombre (requerido)
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  validator: _req,
                ),
                const SizedBox(height: 12),

                // Identificación (opcional)
                TextFormField(
                  controller: _identCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Identificación',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Dirección (opcional)
                TextFormField(
                  controller: _dirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // Teléfono (opcional con validación)
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

                // Email (opcional con validación)
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
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save),
                    label: _saving
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Text('Guardar'),
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
