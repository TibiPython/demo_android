// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// IMPORTA TUS PÁGINAS (ajusta las rutas si difieren en tu proyecto)
import 'features/clientes/ui/clientes_page.dart';
import 'features/prestamos/ui/prestamos_list_page.dart';
import 'features/prestamos/ui/new_loan_page.dart';
import 'features/prestamos/ui/loan_detail_page.dart';
import 'features/cuotas/cuotas_list_page.dart' as cuotas; // class: CuotasListPage

// ========= BACKEND BASE URL =========
// USB con adb reverse (recomendado en desarrollo):
const String kBaseUrl = 'http://127.0.0.1:8000';

// ========= ROUTER =========
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/clientes',
    routes: [
      // Shell con barra inferior (Clientes / Préstamos / Cuotas)
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/clientes',
            pageBuilder: (ctx, st) => const NoTransitionPage(child: ClientesPage()),
          ),
          GoRoute(
            path: '/prestamos',
            pageBuilder: (ctx, st) => const NoTransitionPage(child: PrestamosListPage()),
            routes: [
              // /prestamos/nuevo
              GoRoute(
                path: 'nuevo',
                builder: (ctx, st) => const NewLoanPage(),
              ),
              // /prestamos/:id
              GoRoute(
                path: ':id',
                builder: (ctx, st) {
                  final id = int.parse(st.pathParameters['id']!);
                  return LoanDetailPage(id: id);
                },
              ),
            ],
          ),
          // NUEVO: /cuotas (Gestor de Cuotas)
          GoRoute(
            path: '/cuotas',
            pageBuilder: (ctx, st) => const NoTransitionPage(child: cuotas.CuotasListPage()),
          ),
        ],
      ),
    ],
  );
});

// ========= SHELL CON NAVIGATION BAR =========
class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  int _indexForLocation(String loc) {
    if (loc.startsWith('/prestamos')) return 1;
    if (loc.startsWith('/cuotas')) return 2; // NUEVO
    return 0; // '/clientes' default
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(loc);
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Préstamos')),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (i == 0) context.go('/clientes');
          if (i == 1) context.go('/prestamos');
          if (i == 2) context.go('/cuotas'); // NUEVO
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.request_page), label: 'Préstamos'),
          NavigationDestination(icon: Icon(Icons.payments), label: 'Cuotas'), // NUEVO
        ],
      ),
    );
  }
}

// ========= APP =========
void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    );
  }
}