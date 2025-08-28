import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../loan_service.dart';

class LoanDetailPage extends ConsumerWidget {
  final int id;
  const LoanDetailPage({super.key, required this.id});

  Future<Map<String, dynamic>> _fetch(WidgetRef ref) async {
    final api = ref.read(prestamosApiProvider);
    final data = await api.getById(id);
    return Map<String, dynamic>.from(data);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Préstamo #$id')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetch(ref),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final p = snap.data ?? const {};
          final cliente = p['cliente'] as Map? ?? {};
          final cuotas = List<Map<String, dynamic>>.from(p['cuotas'] ?? const []);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cliente['nombre'] ?? '(sin cliente)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('Código: ${cliente['codigo'] ?? '-'}'),
                        Text('Monto: ${p['monto']}'),
                        Text('Modalidad: ${p['modalidad']}'),
                        Text('Fecha inicio: ${p['fecha_inicio']}'),
                        Text('Cuotas: ${p['num_cuotas']}'),
                        Text('Tasa interés: ${p['tasa_interes']} %'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Cuotas', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...cuotas.map((c) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${c['numero']}')),
                      title: Text('Vence: ${c['fecha_vencimiento']}'),
                      subtitle: Text('Interés a pagar: ${c['interes_a_pagar']}  •  Pagado: ${c['interes_pagado']}'),
                      trailing: Text(c['estado'] ?? ''),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
