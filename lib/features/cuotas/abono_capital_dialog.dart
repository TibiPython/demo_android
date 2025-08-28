// lib/features/cuotas/abono_capital_dialog.dart
import 'package:flutter/material.dart';

class AbonoCapitalResult {
  final double monto;
  final DateTime? fecha;
  AbonoCapitalResult(this.monto, this.fecha);
}

Future<AbonoCapitalResult?> showAbonoCapitalDialog(BuildContext context) async {
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
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monto del abono'),
                validator: (v){
                  final x = double.tryParse(v ?? '');
                  if (x == null || x <= 0) return 'Ingrese un valor válido';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(fecha == null ? 'Fecha: hoy' : 'Fecha: ${fecha!.toIso8601String().substring(0,10)}')),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(now.year-2),
                        lastDate: DateTime(now.year+2),
                        initialDate: now,
                      );
                      if (picked != null) {
                        fecha = picked;
                        (ctx as Element).markNeedsBuild();
                      }
                    },
                    child: const Text('Cambiar fecha'),
                  )
                ],
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: (){
              if(formKey.currentState!.validate()){
                Navigator.pop(ctx, AbonoCapitalResult(double.parse(montoCtrl.text), fecha));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }
  );
}