class Cliente {
  final int id;
  final String codigo;
  final String nombre;
  final String telefono;

  Cliente({required this.id, required this.codigo, required this.nombre, required this.telefono});

  factory Cliente.fromJson(Map<String, dynamic> json) => Cliente(
        id: json['id'] as int,
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
        telefono: json['telefono'] as String,
      );
}

class ClientesResp {
  final int total;
  final List<Cliente> items;
  ClientesResp({required this.total, required this.items});

  factory ClientesResp.fromJson(Map<String, dynamic> json) => ClientesResp(
        total: json['total'] as int,
        items: (json['items'] as List).map((e) => Cliente.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
