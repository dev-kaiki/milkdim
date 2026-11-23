// test/fluxo_pronto_assinaturas_test.dart
//
// Fase A.2 no app: a situação "pronto" (gravada só pelo Controle) e a
// assinatura do pedido (`assinatura_pedido`), separada da assinatura da
// entrega (`assinatura`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/convert.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<String> _caminhoDb() async =>
    join(await databaseFactory.getDatabasesPath(), 'milkdim.db');

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory.deleteDatabase(await _caminhoDb());
}

Future<Map<String, dynamic>> _linha(int id) async {
  final db = await getDb();
  return Map<String, dynamic>.from(
      (await db.query('pedidos', where: 'id = ?', whereArgs: [id])).single);
}

Future<int> _descartados() async {
  final db = await getDb();
  return (await db.rawQuery('SELECT COUNT(*) AS c FROM pedidos_descartados')).first['c']
      as int;
}

/// Assinatura do pedido (PNG mínimo), diferente da de entrega.
final Uint8List _pngPedido = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x02, 0x11, 0x22, 0x33]);
final String _hexPedido = cvt.hex.encode(_pngPedido);
final String _byteaPedido = '\\x$_hexPedido';

/// Assinatura da entrega.
final Uint8List _pngEntrega = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0xab, 0xcd, 0xef]);
final String _byteaEntrega = '\\x${cvt.hex.encode(_pngEntrega)}';

const _idAparelho = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const _cliente = {
  'cliente_nome': 'Padaria Central',
  'cliente_nome_fantasia': '',
  'cliente_telefone': '',
  'cliente_whatsapp': '',
  'cliente_email': '',
  'cliente_endereco': '',
  'cliente_cidade': '',
  'cliente_cpf_cnpj': '',
  'cliente_insc_estadual': '',
  'cliente_cep': '',
  'cliente_anotacao': '',
};

/// Itens como o servidor devolve (jsonb): chaves em outra ordem que a da
/// tela, uma chave a mais e números que a tela recalcularia com ruído.
List<Map<String, dynamic>> _itensDoServidor() => [
      {'nome': 'Leite ninho', 'subtotal': 32.7, 'preco': 10.9, 'quantidade': 3, 'unidade': 'un'},
      {'nome': 'Pudim', 'subtotal': 0.30000000000000004, 'preco': 0.1, 'quantidade': 3},
    ];

/// Os mesmos itens como a tela de edição remonta (ordem do catálogo, chaves
/// da tela e subtotal recalculado).
List<Map<String, dynamic>> _itensDaTela({int qtdPudim = 3}) => [
      {'nome': 'Leite ninho', 'preco': 10.9, 'quantidade': 3, 'subtotal': 10.9 * 3},
      {'nome': 'Pudim', 'preco': 0.1, 'quantidade': qtdPudim, 'subtotal': 0.1 * qtdPudim},
    ];

Map<String, dynamic> _remoto({
  int id = 42,
  String numero = '70',
  String status = 'salvo',
  String datahora = '2026-11-23T09:00:00+00:00',
  Object? assinaturaPedido,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'numero': numero,
      'status': status,
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor',
      'datahora': datahora,
      'total': 33.0,
      'cliente_id': 7,
      'cliente_nome': 'Padaria Central',
      'produtos': _itensDoServidor(),
      'id_aparelho': _idAparelho,
      'enviado_em': '2026-11-23T09:00:01+00:00',
      'finalizado_manual': false,
      if (assinaturaPedido != null) 'assinatura_pedido': assinaturaPedido,
      ...extra,
    };

/// Esquema v17 escrito à mão (copiado do onCreate da v17), para o upgrade real rodar.
Future<void> _criarSchemaV17(Database db, int _) async {
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
      pendente_envio INTEGER NOT NULL DEFAULT 0,
      id_aparelho TEXT,
      so_local INTEGER NOT NULL DEFAULT 0,
      erro_envio TEXT,
      enviado_em TEXT,
      alterado_em TEXT,
      finalizado_em TEXT,
      finalizado_por TEXT,
      finalizado_manual TEXT,
      cancelado_em TEXT,
      cancelado_por TEXT
    );
  ''');
  await db.execute('''
    CREATE TABLE pedidos_descartados (
      id INTEGER PRIMARY KEY AUTOINCREMENT, descartado_em TEXT, motivo TEXT,
      pedido_json TEXT
    );
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
}

void main() {
  final buscaOriginal = buscarRemotoPorNumero;
  final gravarOriginal = gravarPedidoNoServidor;
  late List<Map<String, dynamic>> payloads;

  /// Linha que o servidor falso tem (null = devolve o payload como gravado).
  Map<String, dynamic>? noServidor;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('fluxo_pronto_assinaturas_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await _limpar();
    payloads = [];
    noServidor = null;
    buscarRemotoPorNumero = (n, v) async => null;
    gravarPedidoNoServidor = (payload, {int? idServidor}) async {
      payloads.add(Map<String, dynamic>.from(payload));
      if (noServidor != null) return Map<String, dynamic>.from(noServidor!);
      return {
        ...payload,
        'id': idServidor ?? 100,
        'enviado_em': '2026-11-23T10:00:01+00:00',
        'finalizado_manual': false,
      };
    };
  });

  tearDown(() {
    buscarRemotoPorNumero = buscaOriginal;
    gravarPedidoNoServidor = gravarOriginal;
  });
  tearDownAll(_limpar);

  group('envio', () {
    Map<String, dynamic> novoDaTela({Uint8List? assinaturaPedido, String numero = '80'}) =>
        pedidoDaTela(
          base: {'vendedor_codigo': '0003', 'vendedor_nome': 'Vendedor'},
          numero: numero,
          produtos: _itensDaTela(),
          total: 33.0,
          status: 'salvo',
          datahora: '2026-11-23T10:00:00.000Z',
          clienteId: null,
          cliente: _cliente,
          assinatura: null,
          assinaturaPath: null,
          assinaturaPedido: assinaturaPedido,
          assinaturaPedidoPath: assinaturaPedido == null ? null : '/sig/ped_80.png',
        );

    test('payload leva assinatura_pedido em \\x hex', () async {
      final pedido = novoDaTela(assinaturaPedido: _pngPedido);
      expect(montarPayloadPedido(pedido)['assinatura_pedido'], _byteaPedido);

      final r = await gravarPedidoEEnviar(pedido, novo: true);

      expect(r, ResultadoGravacao.enviado);
      final p = payloads.single;
      expect(p['assinatura_pedido'], _byteaPedido);
      expect(p.containsKey('assinatura'), isFalse,
          reason: 'a assinatura da entrega é outra coisa');
      for (final c in ['assinatura_pedido_path', 'pronto_em', 'pronto_por']) {
        expect(p.containsKey(c), isFalse, reason: '$c não vai ao servidor');
      }

      // O eco ('\x...') volta ao SQLite como hex '0x...' e o caminho fica.
      final l = await _linha(100);
      expect(l['assinatura_pedido'], '0x$_hexPedido');
      expect(assinaturaToBytes(l['assinatura_pedido']), _pngPedido);
      expect(l['assinatura_pedido_path'], '/sig/ped_80.png');
      expect(l['assinatura'], isNull);
    });

    test('payload sem assinatura_pedido nao manda a chave', () async {
      await gravarPedidoEEnviar(novoDaTela(), novo: true);
      expect(payloads.single.containsKey('assinatura_pedido'), isFalse);
      expect(montarPayloadPedido({'assinatura_pedido': null}).containsKey('assinatura_pedido'),
          isFalse);
    });

    test('pedido salvo so com assinatura_pedido_path le o arquivo no envio', () async {
      final dir = await Directory.systemTemp.createTemp('assinatura_pedido_arquivo');
      final arq = File(join(dir.path, 'ped_81.png'));
      await arq.writeAsBytes(_pngPedido);

      final db = await getDb();
      await db.insert('pedidos', {
        'id': kLocalIdBase + 9,
        'numero': '81',
        'vendedor_codigo': '0003',
        'status': 'salvo',
        'total': 20.0,
        'produtos': '[]',
        'datahora': '2026-11-20T10:00:00Z',
        'assinatura_pedido_path': arq.path,
        'pendente_envio': 1,
        'id_aparelho': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      });

      final s = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(s.enviados, 1);
      expect(payloads.single['assinatura_pedido'], _byteaPedido);
      expect(payloads.single.containsKey('assinatura'), isFalse);
      await dir.delete(recursive: true);
    });

    test('as duas assinaturas vao juntas e separadas', () {
      final p = montarPayloadPedido(
          {'assinatura': _pngEntrega, 'assinatura_pedido': '0x$_hexPedido'});
      expect(p['assinatura'], _byteaEntrega);
      expect(p['assinatura_pedido'], _byteaPedido);
    });

    test('gravar sem os bytes da assinatura do pedido nao apaga a guardada', () async {
      await aplicarPedidosRemotos([_remoto(assinaturaPedido: _byteaPedido)]);
      final l = await _linha(42);
      // Mapa parcial (ex.: só a situação): a assinatura do pedido continua.
      await atualizarPedidoLocal({
        'id': 42,
        'numero': '70',
        'vendedor_codigo': '0003',
        'status': 'cancelado',
        'datahora': '2026-11-23T11:00:00Z',
      });
      expect((await _linha(42))['assinatura_pedido'], l['assinatura_pedido']);
      await salvarPedidoLocal({...l, 'assinatura_pedido': null});
      expect((await _linha(42))['assinatura_pedido'], '0x$_hexPedido');
    });
  });

  group('eco e sincronizacao', () {
    test('eco pronto nao e servidorFechou e grava pronto_em', () async {
      await aplicarPedidosRemotos([_remoto(assinaturaPedido: _byteaPedido)]);
      final local = await _linha(42);
      final enviado = {...local, 'datahora': '2026-11-23T11:00:00Z'};
      await atualizarPedidoLocal(enviado);
      final pronto = _remoto(
        status: 'pronto',
        assinaturaPedido: _byteaPedido,
        extra: {'pronto_em': '2026-11-23T10:30:00+00:00', 'pronto_por': '0001'},
      );

      expect(decidirEco(enviado, enviado, pronto), ResultadoEco.aplicado);
      final r = await aplicarEcoDoServidor(enviado: enviado, remoto: pronto);

      expect(r, ResultadoEco.aplicado);
      final l = await _linha(42);
      expect(l['status'], 'pronto');
      expect(l['pronto_em'], '2026-11-23T10:30:00+00:00');
      expect(l['pronto_por'], '0001');
      expect(l['assinatura_pedido'], '0x$_hexPedido');
      expect(l['pendente_envio'], 0);
      expect(await _descartados(), 0, reason: 'pronto não é fechado no Controle');
    });

    test('sync traz assinatura_pedido e pronto', () async {
      await aplicarPedidosRemotos([
        _remoto(
          status: 'pronto',
          assinaturaPedido: _byteaPedido,
          extra: {
            'assinatura': _byteaEntrega,
            'pronto_em': '2026-11-23T10:30:00+00:00',
            'pronto_por': '0001',
          },
        ),
      ]);
      final l = await _linha(42);
      expect(l['status'], 'pronto');
      expect(l['assinatura_pedido'], '0x$_hexPedido');
      expect(signatureToImageBytes(l['assinatura_pedido']), _pngPedido);
      expect(assinaturaToBytes(l['assinatura']), _pngEntrega);
      expect(l['pronto_em'], '2026-11-23T10:30:00+00:00');
      expect(l['pronto_por'], '0001');
      expect(estaPronto(l), isTrue);
      expect(estaEmAberto(l), isTrue);

      // Reabrir o app não muda nada.
      await fecharDbParaTeste();
      expect((await _linha(42))['status'], 'pronto');
    });

    test('copia velha salvo de pedido pronto: eco devolve pronto e a linha local fica pronto',
        () async {
      // O aparelho tem o pedido em aberto e o reenvia (ex.: pendente antigo)
      // depois que a fábrica marcou pronto. O servidor mantém pronto.
      await aplicarPedidosRemotos([_remoto(assinaturaPedido: _byteaPedido)]);
      final local = await _linha(42);
      await atualizarPedidoLocal({...local, 'datahora': '2026-11-23T11:00:00Z'});
      expect((await _linha(42))['pendente_envio'], 1);
      noServidor = _remoto(
        status: 'pronto',
        datahora: '2026-11-23T11:00:00+00:00',
        assinaturaPedido: _byteaPedido,
        extra: {'pronto_em': '2026-11-23T10:30:00+00:00', 'pronto_por': '0001'},
      );

      final s = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(s.enviados, 1);
      expect(payloads.single['status'], 'salvo', reason: 'a cópia velha diz salvo');
      final l = await _linha(42);
      expect(l['status'], 'pronto');
      expect(l['pronto_em'], '2026-11-23T10:30:00+00:00');
      expect(l['pendente_envio'], 0);
      expect(await _descartados(), 0);
      final db = await getDb();
      expect((await db.query('pedidos', where: 'numero = ?', whereArgs: ['70'])).length, 1,
          reason: 'nunca duplica');
    });

    test('reenvio sem mudanca leva produtos iguais aos recebidos do servidor', () async {
      await aplicarPedidosRemotos([_remoto(status: 'pronto', assinaturaPedido: _byteaPedido)]);
      final recebido = jsonEncode(_itensDoServidor());

      // 1) Reenvio da linha do SQLite (pendentes).
      final linha = await _linha(42);
      expect(jsonEncode(montarPayloadPedido(linha)['produtos']), recebido);

      // 2) Salvar pela tela de edição sem mudar itens nem cliente: os itens
      //    remontados pela tela são trocados pelos guardados.
      final daTela = pedidoDaTela(
        base: linha,
        numero: '70',
        produtos: _itensDaTela(),
        total: 10.9 * 3 + 0.1 * 3,
        status: 'salvo',
        datahora: '2026-11-23T11:00:00.000Z',
        clienteId: 7,
        cliente: _cliente,
        assinatura: null,
        assinaturaPath: null,
      );
      expect(itensOuClienteMudaram(linha, daTela), isFalse);
      expect(daTela['status'], 'pronto', reason: 'como o servidor faria');
      expect(precisaAssinaturaDoPedido(original: linha, editado: daTela), isFalse);

      final r = await gravarPedidoEEnviar(daTela, novo: false);
      expect(r, ResultadoGravacao.enviado);
      expect(jsonEncode(payloads.single['produtos']), recebido);
      expect(payloads.single['produtos'], _itensDoServidor());
      expect(payloads.single['cliente_nome'], 'Padaria Central');
    });

    test('tela muda a quantidade: itens novos vao e a situacao volta a salvo', () async {
      await aplicarPedidosRemotos([_remoto(status: 'pronto', assinaturaPedido: _byteaPedido)]);
      final linha = await _linha(42);
      final daTela = pedidoDaTela(
        base: linha,
        numero: '70',
        produtos: _itensDaTela(qtdPudim: 4),
        total: 33.1,
        status: 'pronto',
        datahora: '2026-11-23T11:00:00.000Z',
        clienteId: 7,
        cliente: _cliente,
        assinatura: null,
        assinaturaPath: null,
        assinaturaPedido: _pngPedido,
      );
      expect(itensOuClienteMudaram(linha, daTela), isTrue);
      expect(daTela['status'], 'salvo', reason: 'o vendedor nunca grava pronto');
      expect(daTela['produtos'], _itensDaTela(qtdPudim: 4));
      expect(precisaAssinaturaDoPedido(original: linha, editado: daTela), isTrue);
    });
  });

  group('regras', () {
    final original = {
      'id': 42,
      'status': 'salvo',
      'so_local': 0,
      'cliente_id': 7,
      'cliente_nome': 'Padaria Central',
      'produtos': jsonEncode(_itensDoServidor()),
      'assinatura_pedido': '0x$_hexPedido',
    };
    Map<String, dynamic> editado({
      List<Map<String, dynamic>>? produtos,
      int? clienteId = 7,
      String clienteNome = 'Padaria Central',
    }) =>
        {
          ...original,
          'produtos': produtos ?? _itensDaTela(),
          'cliente_id': clienteId,
          'cliente_nome': clienteNome,
        };

    test('precisaAssinaturaDoPedido: so_local', () {
      expect(
          precisaAssinaturaDoPedido(
              original: {...original, 'so_local': 1}, editado: editado()),
          isTrue);
    });
    test('precisaAssinaturaDoPedido: sem assinatura do pedido', () {
      final semAss = {...original}..remove('assinatura_pedido');
      expect(precisaAssinaturaDoPedido(original: semAss, editado: editado()), isTrue);
      expect(
          precisaAssinaturaDoPedido(
              original: {...semAss, 'assinatura_pedido_path': '/sig/p.png'},
              editado: editado(),
              arquivoExiste: (c) => c == '/sig/p.png'),
          isFalse,
          reason: 'só o arquivo também vale, se existir');
      expect(
          precisaAssinaturaDoPedido(
              original: {...semAss, 'assinatura_pedido_path': '/sig/p.png'},
              editado: editado(),
              arquivoExiste: (_) => false),
          isTrue,
          reason: 'caminho sem arquivo não é assinatura');
    });
    test('precisaAssinaturaDoPedido: com assinatura e itens iguais', () {
      expect(precisaAssinaturaDoPedido(original: original, editado: editado()), isFalse);
    });
    test('precisaAssinaturaDoPedido: quantidade mudou', () {
      expect(
          precisaAssinaturaDoPedido(
              original: original, editado: editado(produtos: _itensDaTela(qtdPudim: 2))),
          isTrue);
    });
    test('precisaAssinaturaDoPedido: cliente mudou', () {
      expect(precisaAssinaturaDoPedido(original: original, editado: editado(clienteId: 8)),
          isTrue);
      expect(
          precisaAssinaturaDoPedido(
              original: original, editado: editado(clienteNome: 'Padaria Nova')),
          isTrue);
    });
    test('itensOuClienteMudaram: preco mudou conta; ordem e subtotal nao', () {
      final caro = _itensDaTela()..[0] = {..._itensDaTela()[0], 'preco': 11.5};
      expect(itensOuClienteMudaram(original, editado(produtos: caro)), isTrue);
      expect(
          itensOuClienteMudaram(
              original, editado(produtos: _itensDaTela().reversed.toList())),
          isFalse);
      final semItem = [_itensDaTela().first];
      expect(itensOuClienteMudaram(original, editado(produtos: semItem)), isTrue);
    });
    test('acaoRemover(pronto) e cancelar', () {
      expect(acaoRemover({'id': 42, 'status': 'pronto', 'so_local': 0}),
          AcaoRemover.cancelar);
    });
    test('estaPronto e estaEmAberto', () {
      expect(estaPronto({'status': 'pronto'}), isTrue);
      expect(estaPronto({'status': 'salvo'}), isFalse);
      for (final st in ['salvo', 'pronto']) {
        expect(estaEmAberto({'status': st}), isTrue);
      }
      for (final st in ['finalizado', 'cancelado']) {
        expect(estaEmAberto({'status': st}), isFalse);
      }
    });
    test('numeroEditavel nao muda com pronto', () {
      expect(numeroEditavel({'id': 42, 'status': 'pronto'}), isFalse);
    });
  });

  test('v17 para v18 so adiciona as colunas e mantem os pedidos', () async {
    final path = await _caminhoDb();
    final v17 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(version: 17, onCreate: _criarSchemaV17));
    await v17.insert('pedidos', {
      'id': 42,
      'numero': '70',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'assinatura': '0x$_hexPedido',
      'pendente_envio': 0,
      'enviado_em': '2026-11-23T09:00:01+00:00',
      'id_aparelho': _idAparelho,
    });
    await v17.insert('pedidos', {
      'id': kLocalIdBase + 1,
      'numero': '71',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'pendente_envio': 0,
      'so_local': 1,
    });
    await v17.close();

    final db = await getDb();
    expect(await db.getVersion(), 18);
    final cols = (await db.rawQuery('PRAGMA table_info(pedidos)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(cols,
        containsAll(['assinatura_pedido', 'assinatura_pedido_path', 'pronto_em', 'pronto_por']));
    final a = await _linha(42);
    expect(a['assinatura'], '0x$_hexPedido');
    expect(a['assinatura_pedido'], isNull);
    expect(a['enviado_em'], '2026-11-23T09:00:01+00:00');
    final b = await _linha(kLocalIdBase + 1);
    expect(b['so_local'], 1);
    expect(b['numero'], '71');
    expect((await db.query('pedidos')).length, 2);

    // Reabrir de novo é idempotente.
    await fecharDbParaTeste();
    expect((await _linha(42))['numero'], '70');
  });
}
