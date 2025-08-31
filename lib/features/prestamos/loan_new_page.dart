import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../core/safe_close.dart'; // <-- helper híbrido
import 'loan_service.dart';

class LoanNewPage extends ConsumerStatefulWidget {
  const LoanNewPage({super.key});

  @override
  ConsumerState<LoanNewPage> createState() => _LoanNewPageState();
}

class _LoanNewPageState extends ConsumerState<LoanNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _codCliCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _numCuotasCtrl = TextEditingController(text: '1');
  final _tasaCtrl = TextEditingController(text: '0');
  DateTime _fechaInicio = DateTime.now();
  String _modalidad = 'Mensual';
  bool _saving = false;

  @override
  void dispose() {
    _codCliCtrl.dispose();
    _montoCtrl.dispose();
    _numCuotasCtrl.dispose();
    _tasaCtrl.dispose();
    super.dispose();
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null;

  String? _num(String? v, {bool integer = false, bool positive = true}) {
    final s = (v ?? '').trim().replaceAll('.', '').replaceAll(',', '.');
    if (s.isEmpty) return 'Requerido';
    final n = num.tryParse(s);
    if (n == null) return 'Número inválido';
    if (positive && n <= 0) return 'Debe ser mayor a 0';
    if (integer && n is! int && n.truncateToDouble() != n.toDouble()) {
      return 'Debe ser entero';
    }
    return null;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _fechaInicio,
    );
    if (d != null) setState(() => _fechaInicio = d);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(prestamosServiceProvider);

      final codCli = _codCliCtrl.text.trim();
      final montoTxt = _montoCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(montoTxt);
      final numCuotas = int.parse(_numCuotasCtrl.text.trim());
      final tasaTxt = _tasaCtrl.text.trim().replaceAll(',', '.');
      final tasaInteres = double.parse(tasaTxt);
      final fechaInicio = _fechaInicio.toIso8601String().substring(0, 10);

      await api.create(
        codCli: codCli,
        monto: monto,
        modalidad: _modalidad,
        fechaInicio: fechaInicio,
        numCuotas: numCuotas,
        tasaInteres: tasaInteres,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Préstamo creado')),
      );
      await SafeClose.pop(context, true); // ← Cierre híbrido
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear: $msg')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo préstamo')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _codCliCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Código cliente (ej. 006)',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _req,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _montoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    validator: (v) => _num(v, integer: false, positive: true),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _modalidad,
                    items: const [
                      DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                      DropdownMenuItem(value: 'Quincenal', child: Text('Quincenal')),
                    ],
                    onChanged: (v) => setState(() => _modalidad = v ?? 'Mensual'),
                    decoration: const InputDecoration(
                      labelText: 'Modalidad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _numCuotasCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Número de cuotas',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => _num(v, integer: true, positive: true),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tasaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tasa de interés (%)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    validator: (v) {
                      final s = (v ?? '').trim().replaceAll(',', '.');
                      if (s.isEmpty) return 'Requerido';
                      final n = num.tryParse(s);
                      if (n == null) return 'Número inválido';
                      if (n < 0) return 'Debe ser >= 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha de inicio',
                      border: OutlineInputBorder(),
                    ),
                    child: InkWell(
                      onTap: _pickDate,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fechaInicio.toIso8601String().substring(0, 10)),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Guardando...' : 'Crear'),
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
    );
  }
}
