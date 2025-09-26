// lib/features/prestamos/ui/new_loan_page.dart

import 'package:flutter/material.dart';
import 'loan_new_page.dart';           // Automático
import 'loan_new_manual_page.dart';    // Manual

class NewLoanPage extends StatelessWidget {
  const NewLoanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo préstamo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _CardOpcion(
              title: 'Préstamo automático',
              subtitle: 'Genera el plan automáticamente según tasa y cuotas',
              icon: Icons.auto_mode,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanNewPage()));
              },
            ),
            const SizedBox(height: 12),
            _CardOpcion(
              title: 'Préstamo manual',
              subtitle: 'Ingresas el plan manualmente (capital/interés por cuota)',
              icon: Icons.edit_note,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoanNewManualPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CardOpcion extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _CardOpcion({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
