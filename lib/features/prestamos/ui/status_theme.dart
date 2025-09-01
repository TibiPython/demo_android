import 'package:flutter/material.dart';

enum LoanStatus { pagado, pendiente, vencido, desconocido }

LoanStatus parseLoanStatus(String? s) {
  final v = (s ?? '').trim().toUpperCase();
  switch (v) {
    case 'PAGADO':
      return LoanStatus.pagado;
    case 'PENDIENTE':
      return LoanStatus.pendiente;
    case 'VENCIDO':
      return LoanStatus.vencido;
    default:
      return LoanStatus.desconocido;
  }
}

class LoanStatusTheme {
  final Color tint;
  final Color border;
  final Color fg;
  final String label;
  final IconData icon;

  LoanStatusTheme({
    required this.tint,
    required this.border,
    required this.fg,
    required this.label,
    required this.icon,
  });

  static LoanStatusTheme of(BuildContext context, String? estadoRaw) {
    final s = parseLoanStatus(estadoRaw);
    switch (s) {
      case LoanStatus.pagado:
        return LoanStatusTheme(
          tint: const Color(0xFF16A34A).withOpacity(0.10),
          border: const Color(0xFF16A34A).withOpacity(0.20),
          fg: const Color(0xFF166534),
          label: 'Pagado',
          icon: Icons.check_circle,
        );
      case LoanStatus.vencido:
        return LoanStatusTheme(
          tint: const Color(0xFFDC2626).withOpacity(0.10),
          border: const Color(0xFFDC2626).withOpacity(0.20),
          fg: const Color(0xFF7F1D1D),
          label: 'Vencido',
          icon: Icons.warning,
        );
      case LoanStatus.pendiente:
        return LoanStatusTheme(
          tint: const Color(0xFFF59E0B).withOpacity(0.12),
          border: const Color(0xFFF59E0B).withOpacity(0.25),
          fg: const Color(0xFF92400E),
          label: 'Pendiente',
          icon: Icons.schedule,
        );
      case LoanStatus.desconocido:
      default:
        final c = Theme.of(context).colorScheme.primary;
        return LoanStatusTheme(
          tint: c.withOpacity(0.06),
          border: c.withOpacity(0.15),
          fg: c.withOpacity(0.80),
          label: estadoRaw ?? '—',
          icon: Icons.info,
        );
    }
  }
}

class LoanStatusBadge extends StatelessWidget {
  final String? estado;
  const LoanStatusBadge({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    final st = LoanStatusTheme.of(context, estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: st.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: st.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(st.icon, size: 16, color: st.fg),
          const SizedBox(width: 6),
          Text(
            st.label,
            style: TextStyle(
              color: st.fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class LoanTintedSection extends StatelessWidget {
  final String? estado;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  const LoanTintedSection({
    super.key,
    required this.estado,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final st = LoanStatusTheme.of(context, estado);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: st.tint,
        border: Border.all(color: st.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
