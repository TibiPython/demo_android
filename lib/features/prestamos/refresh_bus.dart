import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Contador global para anunciar cambios que requieren refrescar la lista de Préstamos.
/// Estrictamente UI: no toca backend ni estado de negocio.
final prestamosRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Helper para anunciar un refresh desde cualquier parte de la app.
void announcePrestamosRefresh(WidgetRef ref) {
  final n = ref.read(prestamosRefreshTickProvider);
  ref.read(prestamosRefreshTickProvider.notifier).state = n + 1;
}
