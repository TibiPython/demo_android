// lib/main_home.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/clientes/clients_page.dart' as clientes; // ClientesPage
import 'features/prestamos/ui/prestamos_list_page.dart' as prestamos_ui; // PrestamosListPage
import 'features/cuotas/cuotas_list_page.dart' as cuotas; // CuotasListPage

void main() => runApp(const ProviderScope(child: MyApp()));

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Préstamos',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const HomeTabs(),
    );
  }
}

class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});
  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int index = 0;
  final pages = <Widget>[
    clientes.ClientesPage(),
    prestamos_ui.PrestamosListPage(),
    cuotas.CuotasListPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Clientes'),
          BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Préstamos'),
          BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Cuotas'),
        ],
      ),
    );
  }
}