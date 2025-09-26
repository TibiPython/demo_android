// lib/features/prestamos/ui/loan_edit_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../loan_service.dart';

class LoanEditPage extends ConsumerStatefulWidget {
  final int prestamoId;
  const LoanEditPage({super.key, required this.prestamoId});

  @override
  ConsumerState<LoanEditPage> createState() => _LoanEditPageState();
}

class _LoanEditPageState extends ConsumerState<LoanEditPage> {
  final _formKey = GlobalKey<FormState>();

  // Cabecera
  final _codCli = TextEditingController();
  final _monto = TextEditingController();
  final _tasa  = TextEditingController();
  final _numCuotas = TextEditingController();
  DateTime _fechaInicio = DateTime.now();
  String _modalidad = 'Mensual';

  // Plan (solo manual)
  List<TextEditingController> _cap = [];
  List<TextEditingController> _int = [];

  bool _loading = true;
  String _planMode = 'auto'; // 'auto' | 'manual'
  String _estado = 'PENDIENTE';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(prestamosApiProvider);
      final data = await api.obtenerPlan(widget.prestamoId);
      _planMode = (data['plan_mode'] ?? 'auto').toString();
      _estado   = (data['estado'] ?? 'PENDIENTE').toString();

      _codCli.text   = (data['cod_cli'] ?? '').toString();
      _monto.text    = (data['monto'] ?? 0).toString();
      _tasa.text     = (data['tasa'] ?? data['tasa_interes'] ?? 0).toString();
      _numCuotas.text= (data['num_cuotas'] ?? 0).toString();
      _modalidad     = (data['modalidad'] ?? 'Mensual').toString();

      final fiStr = (data['fecha_inicio'] ?? '').toString();
      try { _fechaInicio = DateTime.parse(fiStr); } catch (_) {}

      if (_planMode == 'manual') {
        final plan = (data['plan'] as List?) ?? [];
        _cap = List.generate(plan.length, (i) => TextEditingController(text: (plan[i]['capital'] ?? 0).toString()));
        _int = List.generate(plan.length, (i) => TextEditingController(text: (plan[i]['interes'] ?? 0).toString()));
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando: $e')));
      Navigator.pop(context, false);
    }
  }

  double _sum(List<TextEditingController> xs) {
    return xs.fold<double>(0.0, (a, c) {
      final v = double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
      return a + v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isLocked = _estado == 'PAGADO';
    return Scaffold(
      appBar: AppBar(title: const Text('Editar Préstamo')),
      body: Form(
        key: _formKey,
        child: IgnorePointer(
          ignoring: isLocked,
          child: Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (isLocked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Préstamo PAGADO: no se puede editar.', style: TextStyle(color: Colors.red)),
                  ),
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
                      decoration: InputDecoration(labelText: _planMode == 'manual' ? 'Tasa (informativa)' : 'Tasa (%)'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _numCuotas,
                      readOnly: _planMode == 'manual', // mantener longitud del plan en manual
                      decoration: const InputDecoration(labelText: 'Nro. Cuotas'),
                      keyboardType: TextInputType.number,
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

                if (_planMode == 'manual') ...[
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
                ],

                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: isLocked ? null : () async {
                    if (!_formKey.currentState!.validate()) return;
                    try {
                      final api = ref.read(prestamosApiProvider);
                      if (_planMode == 'manual') {
                        final plan = List.generate(_cap.length, (i) => {
                          'capital': double.tryParse(_cap[i].text.replaceAll(',', '.')) ?? 0.0,
                          'interes': double.tryParse(_int[i].text.replaceAll(',', '.')) ?? 0.0,
                        });
                        await api.actualizarPrestamoManual(
                          id: widget.prestamoId,
                          codCli: _codCli.text.trim(),
                          monto: double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0.0,
                          modalidad: _modalidad,
                          fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
                          numCuotas: int.tryParse(_numCuotas.text) ?? plan.length,
                          tasa: double.tryParse(_tasa.text.replaceAll(',', '.')) ?? 0.0,
                          plan: plan.cast<Map<String, double>>(),
                        );
                      } else {
                        await api.actualizarPrestamoAuto(
                          id: widget.prestamoId,
                          codCli: _codCli.text.trim(),
                          monto: double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0.0,
                          modalidad: _modalidad,
                          fechaInicio: DateFormat('yyyy-MM-dd').format(_fechaInicio),
                          numCuotas: int.tryParse(_numCuotas.text) ?? 0,
                          tasaInteres: double.tryParse(_tasa.text.replaceAll(',', '.')) ?? 0.0,
                        );
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo actualizado')));
                      Navigator.pop(context, true);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Guardar cambios'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
