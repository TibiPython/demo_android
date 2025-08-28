// lib/features/prestamos/loan_new_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loan_service.dart';
import 'loan_model.dart';
import 'ui/loan_detail_page.dart';

class LoanNewPage extends ConsumerStatefulWidget {
  const LoanNewPage({super.key});

  @override
  ConsumerState<LoanNewPage> createState() => _LoanNewPageState();
}

class _LoanNewPageState extends ConsumerState<LoanNewPage> {
  final _formKey = GlobalKey<FormState>();

  final _codCliCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _numCuotasCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController();

  DateTime? _fecha;
  String _modalidad = 'MENSUAL';
  bool _saving = false;

  @override
  void dispose() {
    _codCliCtrl.dispose();
    _montoCtrl.dispose();
    _numCuotasCtrl.dispose();
    _tasaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _fecha = picked;
      });
    }
  }

  String _fechaStr() {
    if (_fecha == null) return 'Selecciona fecha';
    // 'YYYY-MM-DD'
    return _fecha!.toIso8601String().split('T').first;
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_fecha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la fecha de inicio')),
      );
      return;
    }

    try {
      setState(() => _saving = true);

      final codCli = _codCliCtrl.text.trim();

      // Permite coma decimal y quita separadores de miles
      final montoTxt = _montoCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(montoTxt);

      final numCuotas = int.parse(_numCuotasCtrl.text.trim());

      final tasaTxt = _tasaCtrl.text.trim().replaceAll(',', '.');
      final tasa = double.parse(tasaTxt);

      final fechaInicio = _fecha!.toIso8601String().split('T').first; // YYYY-MM-DD

      final svc = ref.read(prestamosServiceProvider);

      // svc.crear devuelve Map<String, dynamic> (respuesta del backend)
      final resp = await svc.crear(
        codCli: codCli,
        monto: monto,
        modalidad: _modalidad.toUpperCase(), // 'MENSUAL' | 'QUINCENAL'
        fechaInicio: fechaInicio,
        numCuotas: numCuotas,
        tasaInteres: tasa,
      );

      // A modelo Prestamo
      final prestamo = Prestamo.fromJson(resp);

      if (!mounted) return;
      // 🔧 Corrección aquí: LoanDetailPage espera 'id', NO 'prestamo'
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoanDetailPage(id: prestamo.id)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear préstamo: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo Préstamo')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Código de cliente
                    TextFormField(
                      controller: _codCliCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Código cliente (ej. 006)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),

                    // Monto
                    TextFormField(
                      controller: _montoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Monto',
                        hintText: 'Ej. 1000000',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        final t = v.trim().replaceAll('.', '').replaceAll(',', '.');
                        final d = double.tryParse(t);
                        if (d == null) return 'Número inválido';
                        if (d <= 0) return 'Debe ser mayor a 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Modalidad
                    DropdownButtonFormField<String>(
                      value: _modalidad,
                      items: const [
                        DropdownMenuItem(value: 'MENSUAL', child: Text('Mensual')),
                        DropdownMenuItem(value: 'QUINCENAL', child: Text('Quincenal')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _modalidad = v);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Modalidad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fecha inicio
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFecha,
                            icon: const Icon(Icons.date_range),
                            label: Text(_fechaStr()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Número de cuotas
                    TextFormField(
                      controller: _numCuotasCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Número de cuotas',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        final i = int.tryParse(v.trim());
                        if (i == null) return 'Número inválido';
                        if (i <= 0) return 'Debe ser mayor a 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Tasa de interés
                    TextFormField(
                      controller: _tasaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tasa de interés (%)',
                        hintText: 'Ej. 10.0',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        final t = v.trim().replaceAll(',', '.');
                        final d = double.tryParse(t);
                        if (d == null) return 'Número inválido';
                        if (d < 0) return 'No puede ser negativa';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _guardar,
                        icon: const Icon(Icons.check),
                        label: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
