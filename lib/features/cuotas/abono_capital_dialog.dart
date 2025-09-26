// lib/features/cuotas/abono_capital_dialog.dart
import 'package:flutter/material.dart';
import 'package:demo_android/core/safe_close.dart';

class AbonoCapitalResult {
  final double monto;
  final DateTime? fecha;
  AbonoCapitalResult(this.monto, this.fecha);
}

Future<AbonoCapitalResult?> showAbonoCapitalDialog(BuildContext context, {double? capitalMax}) async {
  final formKey = GlobalKey<FormState>();
  final montoCtrl = TextEditingController();
  DateTime? fecha;

  return showDialog<AbonoCapitalResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Abono a capital'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  border: OutlineInputBorder(),
                ),
                validator: (v){
                  final s = (v ?? '').trim().replaceAll(',', '.');
                  if (s.isEmpty) return 'Requerido';
                  final n = num.tryParse(s);
                  if (n == null) return 'Número inválido';
                  if (n <= 0) return 'Debe ser > 0';
                  if (capitalMax != null && n > capitalMax) return 'Excede capital pendiente (máx: ' + capitalMax!.toStringAsFixed(2) + ')';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(fecha == null ? 'Sin fecha' : 'Fecha: ${fecha!.toIso8601String().substring(0,10)}')),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000,1,1),
                        lastDate: DateTime(2100,12,31),
                        initialDate: DateTime.now(),
                      );
                      if (d != null) {
                        fecha = d;
                        (ctx as Element).markNeedsBuild();
                      }
                    },
                    child: const Text('Elegir fecha'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: ()=> SafeClose.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: (){
              if(formKey.currentState!.validate()){
                final val = double.parse(montoCtrl.text.trim().replaceAll(',', '.'));
                SafeClose.pop(ctx, AbonoCapitalResult(val, fecha));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }
  );
}
