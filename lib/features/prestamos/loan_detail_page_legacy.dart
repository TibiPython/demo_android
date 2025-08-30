import 'package:flutter/material.dart';
import 'loan_model.dart';

class LoanDetailPage extends StatelessWidget {
  final Prestamo prestamo;
  const LoanDetailPage({super.key, required this.prestamo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Préstamo #${prestamo.id} — ${prestamo.cliente['codigo']}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Cliente: ${prestamo.cliente['nombre']} (${prestamo.cliente['codigo']})'),
          Text('Monto: ${prestamo.monto}'),
          Text('Modalidad: ${prestamo.modalidad}'),
          Text('Fecha inicio: ${prestamo.fechaInicio.toString().substring(0,10)}'),
          Text('Cuotas: ${prestamo.numCuotas}  |  Tasa: ${prestamo.tasaInteres}%'),
          const Divider(),
          const Text('Cuotas generadas:'),
          const SizedBox(height: 8),
          ...prestamo.cuotas.map((c) => ListTile(
                title: Text('Cuota ${c.numero} — vence ${c.fechaVencimiento.toString().substring(0,10)}'),
                subtitle: Text('Interés a pagar: ${c.interesAPagar} | Pagado: ${c.interesPagado} | ${c.estado}'),
              )),
        ],
      ),
    );
  }
}
