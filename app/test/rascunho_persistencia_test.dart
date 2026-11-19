// test/rascunho_persistencia_test.dart
//
// Reproduz o bug "rascunho não fica salvo" e valida a correção:
// rascunhos (status='salvo') ganham id numa faixa local reservada (>= kLocalIdBase),
// de modo que a sincronização (que aplica pedidos remotos com INSERT OR REPLACE
// usando o id remoto) nunca sobrescreva um rascunho local por colisão de id.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Garante base limpa
    final p = join(await databaseFactory.getDatabasesPath(), 'milkdim.db');
    await databaseFactory.deleteDatabase(p);
  });

  test('rascunho salvo sobrevive a um sync com id remoto baixo', () async {
    final db = await getDb();

    // 1) Salva um rascunho NOVO (sem id) -> deve receber id na faixa segura.
    await salvarPedidoLocal({
      'numero': '125',
      'produtos': [
        {'nome': 'Leite', 'preco': 5.0, 'quantidade': 2, 'subtotal': 10.0}
      ],
      'total': 10.0,
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Fulano',
      'cliente_nome': 'Cliente Teste',
    });

    final rascunhos = await db.query('pedidos', where: "status = 'salvo'");
    expect(rascunhos.length, 1);
    final rascunhoId = rascunhos.first['id'] as int;
    expect(rascunhoId >= kLocalIdBase, isTrue,
        reason: 'rascunho novo deve usar id na faixa local segura (>= 1e9)');

    // 2) Simula a sincronização trazendo um pedido FINALIZADO do servidor,
    //    com um id serial baixo (como os ids reais do Supabase: 98, 124, ...).
    //    No código antigo, o rascunho teria recebido um id nessa mesma faixa e
    //    seria sobrescrito aqui. Com a faixa segura, isso não acontece.
    await db.insert(
      'pedidos',
      {
        'id': 124, // id remoto típico do Supabase
        'numero': '124',
        'produtos': '[]',
        'total': 0.0,
        'status': 'finalizado',
        'vendedor_codigo': '0003',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 3) O rascunho deve continuar existindo após o "sync".
    final aindaTem = await db.query('pedidos', where: "status = 'salvo'");
    expect(aindaTem.length, 1,
        reason: 'o rascunho NÃO pode sumir após a sincronização');
    expect(aindaTem.first['numero'], '125');

    // E o finalizado também deve estar presente (os dois coexistem).
    final finalizados = await db.query('pedidos', where: "status = 'finalizado'");
    expect(finalizados.length, 1);
    expect(finalizados.first['id'], 124);
  });
}
