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

  // Plan (del backend)
  List<Map<String, dynamic>> _planFull = []; // todas las cuotas (pagadas y pendientes)
  // Editables (solo pendientes)
  List<TextEditingController> _cap = [];
  List<TextEditingController> _int = [];

  int _lastPaidNum = 0;
  String _planMode = 'auto';
  String _estado = 'PENDIENTE';
  bool _loading = true;

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
      _lastPaidNum = int.tryParse('${data['last_paid_num'] ?? 0}') ?? 0;

      _codCli.text   = (data['cod_cli'] ?? '').toString();
      _monto.text    = (data['monto'] ?? 0).toString();
      _tasa.text     = (data['tasa'] ?? data['tasa_interes'] ?? 0).toString();
      _numCuotas.text= (data['num_cuotas'] ?? 0).toString();
      _modalidad     = (data['modalidad'] ?? 'Mensual').toString();

      final fiStr = (data['fecha_inicio'] ?? '').toString();
      try { _fechaInicio = DateTime.parse(fiStr); } catch (_) {}

      _planFull = (data['plan'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Controladores para cuotas pendientes (editables)
      final pendientes = _planFull.where((e) => (e['editable'] == true)).toList();
      _cap = pendientes.map((e) => TextEditingController(text: '${e['capital'] ?? 0}')).toList();
      _int = pendientes.map((e) => TextEditingController(text: '${e['interes'] ?? 0}')).toList();

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

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final moneyFmt = NumberFormat.currency(locale: 'es_CO', symbol: r'$ ');
    final df = DateFormat('yyyy-MM-dd');
    final isLocked = _estado == 'PAGADO';

    final pagadas = _planFull.where((e) => (e['editable'] != true)).toList();
    final pendientesLen = _cap.length;

    // === Cálculos para mostrar el objetivo de capital pendiente ===
    final montoTotal = _toDouble(_monto.text);
    final abonosRealizados = _planFull.fold<double>(0.0, (a, e) => a + _toDouble(e['abono_capital']));
    final capitalObjetivoPendiente = (montoTotal - abonosRealizados).clamp(0, double.infinity);
    final capitalPendienteIngresado = _sum(_cap);
    final diff = (capitalPendienteIngresado - capitalObjetivoPendiente).abs();
    final coincide = diff <= 0.01;

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
                // Aviso de regeneración SIEMPRE
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.6)),
                  ),
                  child: Text(
                    _lastPaidNum == 0
                      ? 'Al guardar, se regenerarán las cuotas desde la cuota #1.'
                      : 'Al guardar, se regenerarán las cuotas pendientes a partir de la cuota #${_lastPaidNum + 1}.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),

                // Capital pendiente objetivo (siempre visible)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Capital pendiente objetivo: ${moneyFmt.format(capitalObjetivoPendiente)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

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
                      onChanged: (_) => setState((){}), // refrescar objetivo si cambian el monto
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
                      readOnly: true, // se recalcula al replanear (pagadas + nuevas)
                      decoration: const InputDecoration(labelText: 'Nro. Cuotas (total)'),
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
                ]),
                const SizedBox(height: 12),

                // Pagadas (solo lectura)
                finalPagadasBlock(pagadas),

                // Pendientes (editables)
                const Text('Cuotas pendientes (editables):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (pendientesLen == 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('No hay cuotas pendientes. Puedes agregar nuevas cuotas abajo.'),
                  ),
                if (pendientesLen > 0)
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
                      for (int i = 0; i < pendientesLen; i++)
                        TableRow(children: [
                          Padding(padding: const EdgeInsets.all(4), child: Text('${_lastPaidNum + 1 + i}')),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: TextField(
                              controller: _cap[i],
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState((){}), // actualiza Σ en vivo
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: TextField(
                              controller: _int[i],
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState((){}),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Builder(builder: (_) {
                              final c = double.tryParse(_cap[i].text.replaceAll(',', '.')) ?? 0.0;
                              final it = double.tryParse(_int[i].text.replaceAll(',', '.')) ?? 0.0;
                              return Text((c + it).toStringAsFixed(2));
                            }),
                          ),
                        ]),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _cap.add(TextEditingController(text: '0'));
                          _int.add(TextEditingController(text: '0'));
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar cuota'),
                    ),
                    const SizedBox(width: 12),
                    // Σ y Objetivo juntos
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Σ Capital pendiente: ${moneyFmt.format(capitalPendienteIngresado)}   •   Objetivo: ${moneyFmt.format(capitalObjetivoPendiente)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: coincide ? Colors.green : Colors.red,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: isLocked ? null : () async {
                    if (!_formKey.currentState!.validate()) return;

                    // Confirmación de regeneración SIEMPRE
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Regeneración de cuotas'),
                        content: Text(
                          _lastPaidNum == 0
                            ? 'Se regenerarán todas las cuotas desde la cuota #1. ¿Deseas continuar?'
                            : 'Se regenerarán las cuotas pendientes a partir de la cuota #${_lastPaidNum + 1}. ¿Deseas continuar?'
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    try {
                      final api = ref.read(prestamosApiProvider);
                      // Plan para pendientes + agregadas
                      final plan = List.generate(_cap.length, (i) => {
                        'capital': double.tryParse(_cap[i].text.replaceAll(',', '.')) ?? 0.0,
                        'interes': double.tryParse(_int[i].text.replaceAll(',', '.')) ?? 0.0,
                      });

                      // Opción: forzar validación client-side antes de enviar (informativo)
                      if (!coincide) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('La suma de capital pendiente no coincide con el objetivo.'))
                        );
                        return;
                      }

                      final resp = await api.replanPrestamo(
                        id: widget.prestamoId,
                        modalidad: _modalidad,           // opcional: puedes cambiar modalidad
                        planPendiente: plan,
                      );
                      if (!mounted) return;
                      final notice = (resp['notice'] ?? 'Plan regenerado').toString();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
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

  // Bloque compacto para mostrar cuotas pagadas en solo lectura
  Widget finalPagadasBlock(List<Map<String, dynamic>> pagadas) {
    if (pagadas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cuotas pagadas (no editables):', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...pagadas.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(width: 28, child: Text('#${e['numero']}')),
              const SizedBox(width: 8),
              Expanded(child: Text('Fecha: ${e['fecha']}')),
              Expanded(child: Text('Cap.: ${(_toDouble(e['abono_capital'])).toStringAsFixed(2)}')),
              Expanded(child: Text('Int. pag.: ${(_toDouble(e['interes_pagado'])).toStringAsFixed(2)}')),
            ],
          ),
        )),
        const Divider(height: 16),
      ],
    );
  }
}
