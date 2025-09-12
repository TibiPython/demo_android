// lib/features/prestamos/ui/loan_new_manual_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../loan_service.dart';

class LoanNewManualPage extends ConsumerStatefulWidget {
  const LoanNewManualPage({super.key});

  @override
  ConsumerState<LoanNewManualPage> createState() => _LoanNewManualPageState();
}

class _LoanNewManualPageState extends ConsumerState<LoanNewManualPage> {
  final _formKey = GlobalKey<FormState>();

  final _codCli = TextEditingController();
  final _monto = TextEditingController();
  final _tasa  = TextEditingController(text: '0');
  final _numCuotas = TextEditingController(text: '3');

  DateTime _fechaInicio = DateTime.now();
  String _modalidad = 'Mensual';

  final List<TextEditingController> _cap = [];
  final List<TextEditingController> _int = [];

  @override
  void initState() {
    super.initState();
    _rebuildPlan();
  }

  void _rebuildPlan() {
    final n = int.tryParse(_numCuotas.text) ?? 0;
    _cap.clear(); _int.clear();
    for (var i = 0; i < n; i++) {
      _cap.add(TextEditingController(text: '0'));
      _int.add(TextEditingController(text: '0'));
    }
    setState(() {});
  }

  double _sum(List<TextEditingController> xs) {
    return xs.fold<double>(0.0, (a, c) {
      final v = double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
      return a + v;
    });
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo Préstamo (Manual)')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _codCli,
                  decoration: const InputDecoration(labelText: 'Código Cliente'),
                  validator: (v) => (v==null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _monto,
                  decoration: const InputDecoration(labelText: 'Monto (total capital)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final x = double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0;
                    return (x <= 0) ? 'Monto inválido' : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _tasa,
                  decoration: const InputDecoration(labelText: 'Tasa (informativa)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _numCuotas,
                  decoration: const InputDecoration(labelText: 'Nro. Cuotas'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _rebuildPlan(),
                  validator: (v) {
                    final x = int.tryParse(v ?? '') ?? 0;
                    return (x <= 0) ? 'Mínimo 1' : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              DropdownButton<String>(
                value: _modalidad,
                items: const [
                  DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                  DropdownMenuItem(value: 'Quincenal', child: Text('Quincenal')),
                ],
                onChanged: (v) => setState(() => _modalidad = v ?? 'Mensual'),
              ),
              const SizedBox(width: 16),
              Text('Inicio: ${df.format(_fechaInicio)}'),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _fechaInicio,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _fechaInicio = d);
                },
                child: const Text('Cambiar'),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Plan por cuota (Capital / Interés):'),
            const SizedBox(height: 6),
            Table(
              columnWidths: const {0: FixedColumnWidth(36), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FixedColumnWidth(100)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(children: [
                  Padding(padding: EdgeInsets.all(4), child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(4), child: Text('Capital', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(4), child: Text('Interés', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(4), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
                ]),
                for (int i = 0; i < _cap.length; i++)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.all(4), child: Text('${i+1}')),
                    Padding(padding: const EdgeInsets.all(4), child: TextField(controller: _cap[i], keyboardType: TextInputType.number)),
                    Padding(padding: const EdgeInsets.all(4), child: TextField(controller: _int[i], keyboardType: TextInputType.number)),
                    Padding(padding: const EdgeInsets.all(4), child: Builder(builder: (_) {
                      final c = double.tryParse(_cap[i].text.replaceAll(',', '.')) ?? 0.0;
                      final it = double.tryParse(_int[i].text.replaceAll(',', '.')) ?? 0.0;
                      return Text((c + it).toStringAsFixed(2));
                    })),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Builder(builder: (_) {
              final sCap = _sum(_cap);
              final m = double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0.0;
              return Text('Σ Capital: ${sCap.toStringAsFixed(2)}  —  Monto: ${m.toStringAsFixed(2)}');
            }),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final plan = List.generate(_cap.length, (i) => {
                  'capital': double.tryParse(_cap[i].text.replaceAll(',', '.')) ?? 0.0,
                  'interes': double.tryParse(_int[i].text.replaceAll(',', '.')) ?? 0.0,
                });
                try {
                  final api = ref.read(prestamosApiProvider);
                  await api.crearPrestamoManual(
                    codCli: _codCli.text.trim(),
                    monto: double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0.0,
                    modalidad: _modalidad,
                    fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
                    numCuotas: int.tryParse(_numCuotas.text) ?? 0,
                    tasa: double.tryParse(_tasa.text.replaceAll(',', '.')) ?? 0.0,
                    plan: plan.cast<Map<String, double>>(),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo manual creado')));
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Crear (Manual)'),
            ),
          ],
        ),
      ),
    );
  }
}
