// test/reabrir_banco_test.dart
//
// Reabrir o banco (reiniciar o app) não pode tirar um pedido em aberto que já
// está no servidor do estado "no servidor", e rascunho antigo de id baixo
// movido para a faixa local fica so_local (apagável, não enviado sozinho).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<String> _caminho() async =>
    join(await databaseFactory.getDatabasesPath(), 'milkdim.db');

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory.deleteDatabase(await _caminho());
}

Future<List<Map<String, Object?>>> _porNumero(String numero) async {
  final db = await getDb();
  return db.query('pedidos', where: 'numero = ?', whereArgs: [numero]);
}

Future<void> _reabrir() async {
  await fecharDbParaTeste();
  await getDb();
}

Map<String, dynamic> _remotoAberto({int id = 42, String numero = '7'}) => {
      'id': id,
      'numero': numero,
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-23T10:00:00+00:00',
      'total': 10.0,
      'cliente_nome': 'Cliente',
      'produtos': [
        {'nome': 'Pudim', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
      ],
      'id_aparelho': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'enviado_em': '2026-11-23T10:00:01+00:00',
      'finalizado_manual': false,
    };

/// Esquema v16 (sem as colunas da v17), para o upgrade real rodar.
Future<void> _criarSchemaV16(Database db, int _) async {
  await db.execute(
      'CREATE TABLE vendedores (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT UNIQUE, nome TEXT, ativo INTEGER);');
  await db.execute('''
    CREATE TABLE clientes (
      id INTEGER PRIMARY KEY, nome TEXT, nome_fantasia TEXT, cpf_cnpj TEXT,
      telefone TEXT, whatsapp TEXT, email TEXT, endereco TEXT, cidade TEXT,
      anotacao TEXT, ativo INTEGER, datahora TEXT, insc_estadual TEXT, cep TEXT
    );
  ''');
  await db.execute(
      'CREATE TABLE produtos (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, nome TEXT, unidade TEXT, preco REAL, ativo INTEGER);');
  await db.execute('''
    CREATE TABLE pedidos (
      id INTEGER PRIMARY KEY AUTOINCREMENT, numero TEXT, produtos TEXT,
      total REAL, status TEXT, datahora TEXT, vendedor_codigo TEXT,
      vendedor_nome TEXT, cliente_id INTEGER, cliente_nome TEXT,
      assinatura TEXT, assinatura_path TEXT, cliente_telefone TEXT,
      cliente_endereco TEXT, cliente_cidade TEXT, cliente_cpf_cnpj TEXT,
      cliente_insc_estadual TEXT, cliente_cep TEXT, cliente_anotacao TEXT,
      cliente_nome_fantasia TEXT, cliente_whatsapp TEXT, cliente_email TEXT,
      pendente_envio INTEGER NOT NULL DEFAULT 0
    );
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('reabrir_banco_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDownAll(_limpar);

  test('pedido aberto vindo do servidor continua no servidor depois de reabrir', () async {
    await aplicarPedidosRemotos([_remotoAberto()]);
    final antes = (await _porNumero('7')).single;
    expect(antes['id'], 42);
    expect(antes['pendente_envio'], 0);

    await _reabrir();

    final depois = (await _porNumero('7')).single;
    expect(depois['id'], 42, reason: 'o id do servidor não pode mudar ao reabrir');
    expect(jaChegouAoServidor(Map<String, dynamic>.from(depois)), isTrue);
    expect(depois['pendente_envio'], 0);
    expect(depois['so_local'], 0);
    expect(depois['enviado_em'], '2026-11-23T10:00:01+00:00');

    // E de novo (cada abertura do app roda o onOpen).
    await _reabrir();
    expect((await _porNumero('7')).single['id'], 42);
  });

  test('pedido aberto do servidor editado e ainda pendente continua no servidor', () async {
    await aplicarPedidosRemotos([_remotoAberto()]);
    final l = Map<String, dynamic>.from((await _porNumero('7')).single);
    await atualizarPedidoLocal({...l, 'total': 25.0, 'so_local': 0});
    expect((await _porNumero('7')).single['pendente_envio'], 1);

    await _reabrir();

    final depois = (await _porNumero('7')).single;
    expect(depois['id'], 42);
    expect(jaChegouAoServidor(Map<String, dynamic>.from(depois)), isTrue);
    expect(depois['pendente_envio'], 1, reason: 'a edição continua aguardando envio');
    expect(depois['total'], 25.0);
  });

  test('rascunho antigo de id baixo e movido para a faixa local como so_local', () async {
    // v16 com um rascunho que ficou na faixa baixa (a relocação da v15 não
    // o pegou): a marcação da v17 só olha a faixa local.
    final v16 = await databaseFactory.openDatabase(await _caminho(),
        options: OpenDatabaseOptions(version: 16, onCreate: _criarSchemaV16));
    await v16.insert('pedidos', {
      'id': 5,
      'numero': '3',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'pendente_envio': 0,
    });
    await v16.close();

    final r = (await _porNumero('3')).single;
    expect(r['id'], kLocalIdBase + 5);
    expect(r['so_local'], 1, reason: 'rascunho antigo: apagável e não enviado sozinho');
    expect(r['pendente_envio'], 0);

    await _reabrir();
    final deNovo = (await _porNumero('3')).single;
    expect(deNovo['id'], kLocalIdBase + 5);
    expect(deNovo['so_local'], 1);
  });
}
