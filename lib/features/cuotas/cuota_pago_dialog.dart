// lib/features/cuotas/cuota_pago_dialog.dart
import 'package:flutter/material.dart';
import 'package:demo_android/core/safe_close.dart';

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
        title: const Text('Pago de interés'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: interesCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Interés pagado',
                  border: OutlineInputBorder(),
                ),
                validator: (v){
                  final s = (v ?? '').trim().replaceAll(',', '.');
                  if (s.isEmpty) return 'Requerido';
                  final n = num.tryParse(s);
                  if (n == null) return 'Número inválido';
                  if (n <= 0) return 'Debe ser > 0';
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
                final val = double.parse(interesCtrl.text.trim().replaceAll(',', '.'));
                SafeClose.pop(ctx, PagoCuotaResult(val, fecha));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }
  );
}
