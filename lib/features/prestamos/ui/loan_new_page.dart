// lib/features/prestamos/ui/loan_new_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../loan_service.dart'; // prestamosApiProvider

class LoanNewPage extends ConsumerStatefulWidget {
  LoanNewPage({super.key});

  @override
  ConsumerState<LoanNewPage> createState() => _LoanNewPageState();
}

class _LoanNewPageState extends ConsumerState<LoanNewPage> {
  final _formKey = GlobalKey<FormState>();

  final _codCliCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController(text: '0');
  final _numCuotasCtrl = TextEditingController(text: '1');

  String _modalidad = 'Mensual'; // "Mensual" | "Quincenal"
  DateTime _fechaInicio = DateTime.now();
  bool _sending = false;

  @override
  void dispose() {
    _codCliCtrl.dispose();
    _montoCtrl.dispose();
    _tasaCtrl.dispose();
    _numCuotasCtrl.dispose();
    super.dispose();
  }

  double _toDouble(String s) {
    final norm = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm) ?? 0.0;
  }

  Future<void> _pickFechaInicio() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _fechaInicio = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final api = ref.read(prestamosApiProvider);
    setState(() => _sending = true);
    try {
      await api.crear(
        codCli: _codCliCtrl.text.trim(),
        monto: _toDouble(_montoCtrl.text),
        modalidad: _modalidad,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        numCuotas: int.tryParse(_numCuotasCtrl.text.trim()) ?? 1,
        tasaInteres: _toDouble(_tasaCtrl.text),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo automático creado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: const Text('Préstamo automático')),
      body: AbsorbPointer(
        absorbing: _sending,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codCliCtrl,
                      decoration: const InputDecoration(labelText: 'Código de cliente', hintText: 'Ej: 005'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _montoCtrl,
                      decoration: const InputDecoration(labelText: 'Monto (capital total)', hintText: 'Ej: 200000'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final d = _toDouble(v ?? '');
                        if (d <= 0) return 'Monto inválido';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tasaCtrl,
                      decoration: const InputDecoration(labelText: 'Tasa de interés (%)', hintText: 'Ej: 10'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final d = _toDouble(v ?? '');
                        if (d < 0) return 'Tasa inválida';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _numCuotasCtrl,
                      decoration: const InputDecoration(labelText: 'Número de cuotas', hintText: 'Ej: 12'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1) return '≥ 1';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _modalidad,
                      decoration: const InputDecoration(labelText: 'Modalidad'),
                      items: const [
                        DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                        DropdownMenuItem(value: 'Quincenal', child: Text('Quincenal')),
                      ],
                      onChanged: (v) => setState(() => _modalidad = v ?? 'Mensual'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: Text('Inicio: ${df.format(_fechaInicio)}')),
                        TextButton.icon(onPressed: _pickFechaInicio, icon: const Icon(Icons.event), label: const Text('Cambiar')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: Text(_sending ? 'Guardando...' : 'Crear (Automático)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
