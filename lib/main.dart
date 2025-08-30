import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/clientes/ui/clientes_page.dart';
import 'features/prestamos/ui/prestamos_list_page.dart';
import 'features/prestamos/ui/new_loan_page.dart';
import 'features/prestamos/ui/loan_detail_page_ui.dart';
import 'features/cuotas/cuotas_list_page.dart' as cuotas;

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/clientes',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _HomeShell(child: child),
        routes: [
          GoRoute(path: '/clientes', builder: (_, __) => const ClientesPage()),
          GoRoute(
            path: '/prestamos',
            builder: (_, __) => const PrestamosListPage(),
            routes: [
              GoRoute(path: 'nuevo', builder: (_, __) => const NewLoanPage()),
              GoRoute(
                path: ':id',
                builder: (_, st) => LoanDetailPageUI(id: int.tryParse(st.pathParameters['id'] ?? '0') ?? 0),
              ),
            ],
          ),
          GoRoute(path: '/cuotas', builder: (_, __) => const cuotas.CuotasListPage()),
        ],
      ),
    ],
  );
});

void main() => runApp(const ProviderScope(child: MyApp()));

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

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.child});
  final Widget child;
  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _indexForLocation(String location) {
    if (location.startsWith('/clientes')) return 0;
    if (location.startsWith('/prestamos')) return 1;
    if (location.startsWith('/cuotas')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (i == 0) context.go('/clientes');
          if (i == 1) context.go('/prestamos');
          if (i == 2) context.go('/cuotas');
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.request_page), label: 'Préstamos'),
          NavigationDestination(icon: Icon(Icons.payments), label: 'Cuotas'),
        ],
      ),
    );
  }
}
