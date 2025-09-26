// lib/features/prestamos/ui/loan_new_manual_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../loan_service.dart'; // prestamosApiProvider

class LoanNewManualPage extends ConsumerStatefulWidget {
  const LoanNewManualPage({super.key});

  @override
  ConsumerState<LoanNewManualPage> createState() => _LoanNewManualPageState();
}

class _LoanNewManualPageState extends ConsumerState<LoanNewManualPage> {
  final _formKey = GlobalKey<FormState>();
  final _cliCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController(text: '0');
  final _numCuotasCtrl = TextEditingController(text: '1');
  DateTime _fechaInicio = DateTime.now();
  String _modalidad = 'Mensual';

  List<Map<String, String>> _plan = [{'capital': '', 'interes': ''}];

  @override
  void dispose() {
    _cliCtrl.dispose();
    _montoCtrl.dispose();
    _tasaCtrl.dispose();
    _numCuotasCtrl.dispose();
    super.dispose();
  }

  double _toDouble(String s) {
    final norm = s.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm) ?? 0.0;
  }

  String _fmt(num v) => NumberFormat.decimalPattern('es_CO').format(v);

  void _syncPlanLength() {
    final n = (int.tryParse(_numCuotasCtrl.text.trim()) ?? 1).clamp(1, 240);
    if (_plan.length < n) {
      _plan.addAll(List.generate(n - _plan.length, (_) => {'capital': '', 'interes': ''}));
    } else if (_plan.length > n) {
      _plan = _plan.sublist(0, n);
    }
    setState(() {});
  }

  String? _validarPlan() {
    const tol = 0.01;
    final monto = _toDouble(_montoCtrl.text);
    final tasa = _toDouble(_tasaCtrl.text);
    final n = int.tryParse(_numCuotasCtrl.text.trim()) ?? _plan.length;

    if (monto <= 0) return 'El monto debe ser mayor a 0';
    if (tasa < 0) return 'La tasa no puede ser negativa';
    if (n != _plan.length) return 'El número de cuotas no coincide con el plan';

    double saldo = monto, sumaCapital = 0.0;
    for (int i = 0; i < n; i++) {
      final cap = _toDouble(_plan[i]['capital'] ?? '');
      final inte = _toDouble(_plan[i]['interes'] ?? '');
      if (cap < -tol || inte < -tol) return 'Cuota ${i + 1}: capital/interés no pueden ser negativos';

      final base = (i == 0) ? monto : saldo;
      final interesEsp = (base * tasa / 100.0);
      final interesEspR = (interesEsp * 100).roundToDouble() / 100.0;
      if ((inte - interesEspR).abs() > tol) return 'Cuota ${i + 1}: interés ${_fmt(inte)} no coincide con ${_fmt(interesEspR)}';

      saldo = ((saldo - cap) * 100).roundToDouble() / 100.0;
      if (saldo < -tol) return 'Cuota ${i + 1}: el capital deja saldo negativo (${_fmt(saldo)})';

      sumaCapital = ((sumaCapital + cap) * 100).roundToDouble() / 100.0;
    }
    if ((sumaCapital - monto).abs() > tol) return 'La suma de capital (${_fmt(sumaCapital)}) debe igualar el monto (${_fmt(monto)})';
    if (saldo.abs() > tol) return 'El saldo final debe ser 0 (actual: ${_fmt(saldo)})';
    return null;
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
    _syncPlanLength();

    final err = _validarPlan();
    if (err != null) {
      _showSnack(err);
      return;
    }

    try {
      final api = ref.read(prestamosApiProvider);
      final n = int.tryParse(_numCuotasCtrl.text.trim()) ?? _plan.length;
      final planPayload = List.generate(n, (i) => {
            'capital': _toDouble(_plan[i]['capital'] ?? '0'),
            'interes': _toDouble(_plan[i]['interes'] ?? '0'),
          });

      await api.crearManual(
        codCli: _cliCtrl.text.trim(),
        monto: _toDouble(_montoCtrl.text),
        tasa: _toDouble(_tasaCtrl.text),
        modalidad: _modalidad,
        numCuotas: n,
        fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
        plan: planPayload,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo manual creado')));
    } on DioException catch (e) {
      final msg = e.response?.data is Map && (e.response?.data['detail'] != null)
          ? e.response?.data['detail'].toString()
          : (e.message ?? 'Error inesperado');
      _showSnack('No se pudo crear: $msg');
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo Préstamo (Manual)')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cliCtrl,
                    decoration: const InputDecoration(labelText: 'Código Cliente'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _montoCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monto (total capital)'),
                    validator: (v) {
                      final x = _toDouble(v ?? '');
                      if (x <= 0) return 'Monto > 0';
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
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tasa (%)'),
                    validator: (v) {
                      final x = _toDouble(v ?? '');
                      if (x < 0) return 'No negativa';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _numCuotasCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nro. Cuotas'),
                    onChanged: (_) => _syncPlanLength(),
                    validator: (v) {
                      final x = int.tryParse((v ?? '').trim());
                      if (x == null || x <= 0) return '≥ 1';
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
                    items: const [
                      DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                      DropdownMenuItem(value: 'Quincenal', child: Text('Quincenal')), // corregido
                    ],
                    onChanged: (v) => setState(() => _modalidad = v ?? 'Mensual'),
                    decoration: const InputDecoration(labelText: 'Modalidad'),
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
            const SizedBox(height: 16),

            Text('Plan por cuota (Capital / Interés):', style: Theme.of(context).textTheme.titleMedium),

            const SizedBox(height: 8),
            for (int i = 0; i < _plan.length; i++) ...[
              Row(
                children: [
                  SizedBox(width: 28, child: Text('${i + 1}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _plan[i]['capital'],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capital'),
                      onChanged: (v) => _plan[i]['capital'] = v,
                      validator: (v) {
                        final x = _toDouble(v ?? '');
                        if (x < 0) return '≥ 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _plan[i]['interes'],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Interés'),
                      onChanged: (v) => _plan[i]['interes'] = v,
                      validator: (v) {
                        final x = _toDouble(v ?? '');
                        if (x < 0) return '≥ 0';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 8),
            FilledButton(onPressed: _submit, child: const Text('Crear (Manual)')),
          ],
        ),
      ),
    );
  }
}
