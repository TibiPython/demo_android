// lib/features/cuotas/cuota_pago_dialog.dart
import 'package:flutter/material.dart';

class PagoCuotaResult {
  final double interesPagado;
  final DateTime? fechaPago;
  PagoCuotaResult(this.interesPagado, this.fechaPago);
}

Future<PagoCuotaResult?> showPagoCuotaDialog(BuildContext context, {double? sugerido}) async {
  final formKey = GlobalKey<FormState>();
  final interesCtrl = TextEditingController(text: sugerido == null ? '' : sugerido.toStringAsFixed(0));
  DateTime? fecha;
  return showDialog<PagoCuotaResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Pagar interés'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: interesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Interés a pagar'),
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
                Navigator.pop(ctx, PagoCuotaResult(double.parse(interesCtrl.text), fecha));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }
  );
}