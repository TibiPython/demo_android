import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart' show GoRouter;

/// Cierre híbrido seguro:
/// - Usa go_router si está disponible: gr.pop(result)
/// - Si no, Navigator.pop(result) sólo si se puede hacer pop
class SafeClose {
  static Future<void> pop(BuildContext context, [Object? result]) async {
    try {
      final gr = GoRouter.maybeOf(context);
      if (gr != null) {
        gr.pop(result);
        return;
      }
    } catch (_) {
      // No hay go_router en este árbol
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }
}
