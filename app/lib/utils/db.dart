// lib/utils/db.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:convert/convert.dart' as hex_conv;

import 'id_aparelho.dart';

sq.Database? _db;

/// ⬆️ aumente quando mudar o schema
const _dbVersion = 17;

/// Faixa reservada para IDs de pedidos criados SOMENTE localmente (rascunhos).
///
/// Os IDs do Supabase são seriais "baixos" (1, 2, 3, ...). O SQLite, por
/// AUTOINCREMENT, atribuía IDs aos rascunhos no MESMO intervalo. Como a
/// sincronização aplica os pedidos remotos com `INSERT OR REPLACE` usando o id
/// remoto como chave primária local, um pedido finalizado vindo do servidor
/// acabava sobrescrevendo (REPLACE) um rascunho local que tinha o mesmo id —
/// fazendo o rascunho "sumir" após salvar.
///
/// Reservando IDs locais a partir de 1e9, os dois espaços nunca colidem.
const int kLocalIdBase = 1000000000; // 1e9

/// Próximo id seguro (>= [kLocalIdBase]) para um pedido local novo.
/// Aceita tanto [sq.Database] quanto [sq.Transaction] (ambos são DatabaseExecutor).
Future<int> proximoIdLocalSeguro(sq.DatabaseExecutor db) async {
  final r = await db.rawQuery(
    'SELECT MAX(id) AS m FROM pedidos WHERE id >= ?',
    [kLocalIdBase],
  );
  final m = r.isNotEmpty ? r.first['m'] : null;
  final base = (m is int) ? m : (m is num ? m.toInt() : kLocalIdBase - 1);
  return base + 1;
}

/// Move rascunhos (status='salvo') com id "baixo" para a faixa reservada,
/// evitando colisão com os ids do Supabase na próxima sincronização.
/// Idempotente (só age sobre id < [kLocalIdBase]).
Future<void> _relocarRascunhosParaFaixaSegura(sq.DatabaseExecutor db) async {
  try {
    await db.execute(
      "UPDATE pedidos SET id = id + $kLocalIdBase "
      "WHERE status = 'salvo' AND id < $kLocalIdBase",
    );
  } catch (e) {
    debugPrint('Falha ao relocar rascunhos para faixa segura: $e');
  }
}

/// Recria `vendedores` sem a coluna `senha`, mantendo as linhas. Idempotente.
Future<void> _recriarVendedoresSemSenha(sq.DatabaseExecutor db) async {
  final info = await db.rawQuery('PRAGMA table_info(vendedores)');
  final cols = info.map((r) => r['name'] as String).toSet();
  if (!cols.contains('senha')) return;
  await db.execute('DROP TABLE IF EXISTS vendedores_new');
  await db.execute('''
    CREATE TABLE vendedores_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigo TEXT UNIQUE,
      nome TEXT,
      ativo INTEGER
    );
  ''');
  await db.execute(
    'INSERT INTO vendedores_new (id, codigo, nome, ativo) '
    'SELECT id, codigo, nome, ativo FROM vendedores',
  );
  await db.execute('DROP TABLE vendedores');
  await db.execute('ALTER TABLE vendedores_new RENAME TO vendedores');
}

/// Fecha o banco em cache (testes que montam um banco antigo à mão).
@visibleForTesting
Future<void> fecharDbParaTeste() async {
  final d = _db;
  _db = null;
  if (d != null) await d.close();
}

/// Abre/cria o banco local
Future<sq.Database> getDb() async {
  if (_db != null) return _db!;
  final path = join(await sq.getDatabasesPath(), 'milkdim.db');

  _db = await sq.openDatabase(
    path,
    version: _dbVersion,
    onCreate: (db, _) async {
      // VENDEDORES
      await db.execute('''
        CREATE TABLE vendedores (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          codigo TEXT UNIQUE,
          nome TEXT,
          ativo INTEGER
        );
      ''');

      // CLIENTES
      await db.execute('''
        CREATE TABLE clientes (
          id INTEGER PRIMARY KEY,
          nome TEXT,
          nome_fantasia TEXT,
          cpf_cnpj TEXT,
          telefone TEXT,
          whatsapp TEXT,
          email TEXT,
          endereco TEXT,
          cidade TEXT,
          anotacao TEXT,
          ativo INTEGER,
          datahora TEXT,
          insc_estadual TEXT,
          cep TEXT
        );
      ''');

      // PRODUTOS (com 'codigo' e 'unidade')
      await db.execute('''
        CREATE TABLE produtos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          codigo TEXT,
          nome TEXT,
          unidade TEXT,
          preco REAL,
          ativo INTEGER
        );
      ''');

      // PEDIDOS (agora com assinatura_path)
      await db.execute('''
        CREATE TABLE pedidos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          numero TEXT,
          produtos TEXT,           -- JSON string
          total REAL,
          status TEXT,             -- salvo | finalizado
          datahora TEXT,           -- ISO 8601 (UTC)
          vendedor_codigo TEXT,
          vendedor_nome TEXT,
          cliente_id INTEGER,
          cliente_nome TEXT,
          assinatura TEXT,         -- hex "0x..." (legado/compatibilidade)
          assinatura_path TEXT,    -- caminho do PNG/JPEG local da assinatura
          cliente_telefone TEXT,
          cliente_endereco TEXT,
          cliente_cidade TEXT,
          cliente_cpf_cnpj TEXT,
          cliente_insc_estadual TEXT,
          cliente_cep TEXT,
          cliente_anotacao TEXT,
          cliente_nome_fantasia TEXT,
          cliente_whatsapp TEXT,
          cliente_email TEXT,
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
      await _criarTabelaDescartados(db);

      // Índices úteis
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_cliente_data ON pedidos(cliente_id, datahora);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor_data ON pedidos(vendedor_codigo, datahora);');

      // ✅ evita duplicação do mesmo pedido do mesmo vendedor
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
    },
    onUpgrade: (db, oldV, newV) async {
      if (oldV < 8) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_cliente_data ON pedidos(cliente_id, datahora);');
      }
      if (oldV < 9) {
        await _ensureColumn(db, 'produtos', 'codigo', 'TEXT');
        await _ensureColumn(db, 'produtos', 'unidade', 'TEXT');
      }
      if (oldV < 10) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor_data ON pedidos(vendedor_codigo, datahora);');
      }
      if (oldV < 11) {
        await _dedupPedidosByNumeroVendedor(db);
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
      }
      // v12: sem mudanças de schema; apenas helpers novos.
      if (oldV < 13) {
        // v13: adiciona coluna para caminho do arquivo de assinatura
        await _ensureColumn(db, 'pedidos', 'assinatura_path', 'TEXT');
      }
      if (oldV < 15) {
        // v15: separa o espaço de ids dos rascunhos locais do serial do Supabase,
        // para que a sincronização não sobrescreva rascunhos por colisão de id.
        await _relocarRascunhosParaFaixaSegura(db);
      }
      if (oldV < 16) {
        // v16: pedidos finalizados offline ficam marcados para reenvio e a
        // senha em texto puro some da tabela local de vendedores.
        await _ensureColumn(db, 'pedidos', 'pendente_envio', 'INTEGER NOT NULL DEFAULT 0');
        await db.execute(
          "UPDATE pedidos SET pendente_envio = 1 "
          "WHERE status = 'finalizado' AND id >= $kLocalIdBase",
        );
        await _recriarVendedoresSemSenha(db);
      }
      if (oldV < 17) {
        // v17: pedido aberto/cancelado também sobe ao servidor; todo pedido
        // ganha id_aparelho. Rascunhos antigos (nunca enviados) ficam so_local.
        await _garantirSchemaV17(db);
        await db.execute(
          "UPDATE pedidos SET so_local = 1 "
          "WHERE status = 'salvo' AND id >= $kLocalIdBase AND pendente_envio = 0",
        );
      }
    },
    onOpen: (db) async {
      await _ensureColumn(db, 'produtos', 'codigo', 'TEXT');
      await _ensureColumn(db, 'produtos', 'unidade', 'TEXT');

      // Garante índices (idempotente)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_cliente_data ON pedidos(cliente_id, datahora);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_vendedor_data ON pedidos(vendedor_codigo, datahora);');
      try {
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
      } catch (e) {
        debugPrint('Falha ao garantir índice único ux_pedidos_num_vend: $e');
      }

      // Garante coluna nova mesmo se a base já existia (idempotente)
      await _ensureColumn(db, 'pedidos', 'assinatura_path', 'TEXT');
      await _ensureColumn(db, 'pedidos', 'pendente_envio', 'INTEGER NOT NULL DEFAULT 0');
      await _garantirSchemaV17(db);

      // Segurança extra: garante que rascunhos antigos estejam na faixa de id
      // reservada (caso o app tenha pulado o onUpgrade por algum motivo).
      await _relocarRascunhosParaFaixaSegura(db);
    },
  );
  return _db!;
}

/// ---------- Utils de migração/colunas ----------

Future<void> _criarTabelaDescartados(sq.DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS pedidos_descartados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      descartado_em TEXT,
      motivo TEXT,
      pedido_json TEXT
    );
  ''');
}

/// Colunas e tabela da v17 (idempotente).
Future<void> _garantirSchemaV17(sq.Database db) async {
  await _ensureColumn(db, 'pedidos', 'id_aparelho', 'TEXT');
  await _ensureColumn(db, 'pedidos', 'so_local', 'INTEGER NOT NULL DEFAULT 0');
  await _ensureColumn(db, 'pedidos', 'erro_envio', 'TEXT');
  for (final c in const [
    'enviado_em',
    'alterado_em',
    'finalizado_em',
    'finalizado_por',
    'finalizado_manual',
    'cancelado_em',
    'cancelado_por',
  ]) {
    await _ensureColumn(db, 'pedidos', c, 'TEXT');
  }
  await _criarTabelaDescartados(db);
}

Future<Set<String>> _getTableColumns(sq.Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => (r['name'] as String)).toSet();
}

Future<void> _ensureColumn(sq.Database db, String table, String column, String type) async {
  try {
    final cols = await _getTableColumns(db, table);
    if (!cols.contains(column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
      debugPrint('Adicionada coluna $column em $table ($type)');
    }
  } catch (e) {
    debugPrint('Falha ao garantir coluna $column em $table: $e');
  }
}

Future<Map<String, dynamic>> _filterToTableColumns(
    sq.Database db,
    String table,
    Map<String, dynamic> data,
    ) async {
  final cols = await _getTableColumns(db, table);
  final out = <String, dynamic>{};
  for (final e in data.entries) {
    if (cols.contains(e.key)) out[e.key] = e.value;
  }
  return out;
}

Future<void> _insertOrReplaceFiltered(
    sq.Database db,
    String table,
    Map<String, dynamic> data,
    ) async {
  final filtered = await _filterToTableColumns(db, table, data);
  await db.insert(table, filtered, conflictAlgorithm: sq.ConflictAlgorithm.replace);
}

/// Converte bytes (assinatura) para string hex "0x...".
String? _bytesToHex0x(dynamic assinatura) {
  if (assinatura == null) return null;
  if (assinatura is Uint8List) {
    return '0x${hex_conv.hex.encode(assinatura)}';
  }
  if (assinatura is List<int>) {
    return '0x${hex_conv.hex.encode(Uint8List.fromList(assinatura))}';
  }
  if (assinatura is String) {
    final s = assinatura.startsWith('0x') ? assinatura.substring(2) : assinatura;
    final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
    if (isHex) return assinatura.startsWith('0x') ? assinatura : '0x$s';
  }
  return null;
}

/// Garante que o campo 'produtos' esteja em JSON string
String _ensureProdutosJson(dynamic produtos) {
  if (produtos == null) return '[]';
  if (produtos is String) return produtos;
  try {
    return jsonEncode(produtos);
  } catch (_) {
    return '[]';
  }
}

/// -------- VENDEDORES --------

Future<void> salvarVendedorLocal(Map<String, dynamic> vendedor) async {
  final db = await getDb();
  final v = {
    'codigo': vendedor['codigo']?.toString(),
    'nome': vendedor['nome']?.toString(),
    'ativo': (vendedor['ativo'] is bool)
        ? (vendedor['ativo'] ? 1 : 0)
        : (vendedor['ativo'] is int ? vendedor['ativo'] : 1),
  };
  // Só o vendedor logado fica no aparelho.
  final filtered = await _filterToTableColumns(db, 'vendedores', v);
  await db.transaction((txn) async {
    await txn.delete('vendedores', where: 'codigo IS NOT ?', whereArgs: [v['codigo']]);
    await txn.insert('vendedores', filtered, conflictAlgorithm: sq.ConflictAlgorithm.replace);
  });
}

/// -------- CLIENTES --------

Future<void> salvarClienteLocal(Map<String, dynamic> cliente) async {
  final db = await getDb();
  final map = {
    'id': cliente['id'],
    'nome': cliente['nome'],
    'nome_fantasia': cliente['nome_fantasia'],
    'cpf_cnpj': cliente['cpf_cnpj'],
    'telefone': cliente['telefone'],
    'whatsapp': cliente['whatsapp'],
    'email': cliente['email'],
    'endereco': cliente['endereco'],
    'cidade': cliente['cidade'],
    'anotacao': cliente['anotacao'],
    'ativo': (cliente['ativo'] is bool)
        ? (cliente['ativo'] ? 1 : 0)
        : (cliente['ativo'] is int ? cliente['ativo'] : 1),
    'datahora': cliente['datahora'] ?? DateTime.now().toUtc().toIso8601String(),
    'insc_estadual': cliente['insc_estadual'],
    'cep': cliente['cep'],
  };
  await _insertOrReplaceFiltered(db, 'clientes', map);
}

Future<List<Map<String, dynamic>>> listarClientes() async {
  final db = await getDb();
  return db.query('clientes', orderBy: 'nome COLLATE NOCASE ASC');
}

/// -------- PRODUTOS --------

Future<List<Map<String, dynamic>>> listarProdutos() async {
  final db = await getDb();
  return db.query(
    'produtos',
    columns: ['id', 'nome', 'preco'],
    where: 'ativo IS NULL OR ativo = 1',
    orderBy: 'nome COLLATE NOCASE ASC',
  );
}

Future<void> salvarProdutoLocal(Map<String, dynamic> produto) async {
  final db = await getDb();
  final p = {
    'id': produto['id'],
    'codigo': produto['codigo'],
    'nome': produto['nome'],
    'unidade': produto['unidade'],
    'preco': (produto['preco'] is num) ? (produto['preco'] as num).toDouble() : 0.0,
    'ativo': (produto['ativo'] is bool)
        ? (produto['ativo'] ? 1 : 0)
        : (produto['ativo'] is int ? produto['ativo'] : 1),
  };
  await _insertOrReplaceFiltered(db, 'produtos', p);
}

/// -------- PEDIDOS --------

/// Campos que só o app local controla: so_local, pendente_envio, id_aparelho
/// (e, no REPLACE, os campos locais/cópias do servidor que não vieram no mapa).
/// [map] precisa ter 'id'.
Future<void> _aplicarCamposLocais(
  sq.Database db,
  Map<String, dynamic> map,
  Map<String, dynamic> pedido, {
  required bool replace,
}) async {
  final ex = await db.query('pedidos', where: 'id = ?', whereArgs: [map['id']], limit: 1);
  final antigo = ex.isEmpty ? null : ex.first;

  int soLocal;
  if (pedido.containsKey('so_local') && pedido['so_local'] != null) {
    final v = pedido['so_local'];
    soLocal = (v == true || v == 1 || '$v' == '1') ? 1 : 0;
  } else {
    soLocal = (antigo?['so_local'] as num?)?.toInt() ?? 0;
  }
  map['so_local'] = soLocal;
  map['pendente_envio'] = soLocal == 1 ? 0 : 1;

  final guardado = antigo?['id_aparelho']?.toString() ?? '';
  final vindo = pedido['id_aparelho']?.toString() ?? '';
  map['id_aparelho'] = guardado.isNotEmpty
      ? guardado
      : (vindo.isNotEmpty ? vindo : novoIdAparelho());

  if (replace && antigo != null) {
    // INSERT OR REPLACE apagaria o que não está no mapa: preserva.
    for (final c in const [
      'erro_envio',
      'enviado_em',
      'alterado_em',
      'finalizado_em',
      'finalizado_por',
      'finalizado_manual',
      'cancelado_em',
      'cancelado_por',
    ]) {
      if (pedido.containsKey(c)) {
        map[c] = pedido[c]?.toString();
      } else {
        map[c] = antigo[c];
      }
    }
  } else {
    for (final c in const [
      'erro_envio',
      'enviado_em',
      'alterado_em',
      'finalizado_em',
      'finalizado_por',
      'finalizado_manual',
      'cancelado_em',
      'cancelado_por',
    ]) {
      if (pedido.containsKey(c)) map[c] = pedido[c]?.toString();
    }
  }
}

/// Valor de `erro_envio` quando o número já é de outro pedido no servidor.
const String kErroNumeroEmUso = 'numero';

/// O `(numero, vendedor_codigo)` já é de outro pedido: no servidor (com outro
/// `id_aparelho`, lançada pelo envio) ou no aparelho (um pedido já enviado ou
/// outra linha local, lançada pela gravação local antes de escrever qualquer
/// coisa: o índice único local apagaria a outra linha). Nada é perdido; o
/// vendedor precisa trocar o número.
class NumeroEmUso implements Exception {
  const NumeroEmUso(this.numero, this.vendedorCodigo);
  final String numero;
  final String vendedorCodigo;

  @override
  String toString() =>
      'NumeroEmUso: o número $numero do vendedor $vendedorCodigo já é de outro pedido';
}

/// Linha local que um pedido NOVO pode reaproveitar (mesmo numero+vendedor):
/// só as que nunca chegaram ao servidor.
bool _reaproveitavel(Map<String, Object?> l) {
  final id = (l['id'] as num?)?.toInt() ?? 0;
  if ((l['so_local'] as num?)?.toInt() == 1) return true;
  if (id < kLocalIdBase) return false;
  return (l['pendente_envio'] as num?)?.toInt() == 1 || l['status']?.toString() == 'salvo';
}

/// Outra linha (id diferente de [id]) com o mesmo (numero, vendedor), ou null.
Future<Map<String, Object?>?> _outraComMesmoNumero(
    sq.DatabaseExecutor db, String? numero, String? vend, int? id) async {
  if (numero == null || numero.isEmpty || vend == null || vend.isEmpty) return null;
  final r = await db.query(
    'pedidos',
    columns: ['id', 'so_local', 'pendente_envio', 'status', 'id_aparelho'],
    where: id == null
        ? 'numero = ? AND vendedor_codigo = ?'
        : 'numero = ? AND vendedor_codigo = ? AND id <> ?',
    whereArgs: id == null ? [numero, vend] : [numero, vend, id],
    limit: 1,
  );
  return r.isEmpty ? null : r.first;
}

/// Id em que a gravação de um pedido com [id] deve cair.
/// 1. Não existe mais linha com [id] e alguma linha tem o mesmo id_aparelho
///    (não vazio): é o mesmo pedido, cujo eco trocou o id local pelo do
///    servidor enquanto a tela estava aberta (o número pode ter mudado na
///    tela). A gravação vai para o id dessa linha.
/// 2. Outra linha (fora o alvo) com o mesmo (numero, vendedor):
///    [NumeroEmUso] (gravar apagaria a outra pelo índice único).
/// 3. Senão: o alvo.
Future<int> _idDaGravacao(sq.DatabaseExecutor db, int id, String? numero,
    String? vend, Object? idAparelho) async {
  var alvo = id;
  final existe = await db.query('pedidos',
      columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
  final meu = idAparelho?.toString().trim() ?? '';
  if (existe.isEmpty && meu.isNotEmpty) {
    final mesmo = await db.query('pedidos',
        columns: ['id'], where: 'id_aparelho = ?', whereArgs: [meu], limit: 1);
    if (mesmo.isNotEmpty) alvo = (mesmo.first['id'] as num).toInt();
  }
  if (await _outraComMesmoNumero(db, numero, vend, alvo) != null) {
    throw NumeroEmUso(numero!, vend!);
  }
  return alvo;
}

/// O pedido já existe no servidor (id serial baixo, fora da faixa local).
bool jaChegouAoServidor(Map<String, dynamic> pedido) {
  final raw = pedido['id'];
  final id = raw is int ? raw : int.tryParse('${raw ?? ''}');
  return id != null && id < kLocalIdBase;
}

/// Guarda uma cópia (JSON) de uma versão local que foi substituída/descartada.
/// Dentro de uma transação, passe-a em [em] (usar o banco direto travaria).
Future<void> guardarVersaoDescartada(
  Map<String, dynamic> pedido,
  String motivo, {
  sq.DatabaseExecutor? em,
}) async {
  final db = em ?? await getDb();
  await db.insert('pedidos_descartados', {
    'descartado_em': DateTime.now().toUtc().toIso8601String(),
    'motivo': motivo,
    'pedido_json': jsonEncode(pedido, toEncodable: (o) => o.toString()),
  });
}

/// Grava o pedido e devolve o id da linha gravada.
Future<int> salvarPedidoLocal(Map<String, dynamic> pedido) async {
  final db = await getDb();
  final map = <String, dynamic>{
    'numero': pedido['numero']?.toString(),
    // 'id' é definido logo abaixo (faixa local segura para rascunhos novos)
    'produtos': _ensureProdutosJson(pedido['produtos']),
    'total': (pedido['total'] is num) ? (pedido['total'] as num).toDouble() : 0.0,
    'status': (pedido['status'] ?? 'salvo').toString(),
    'datahora': (pedido['datahora'] is String && (pedido['datahora'] as String).isNotEmpty)
        ? pedido['datahora']
        : DateTime.now().toUtc().toIso8601String(),
    'vendedor_codigo': pedido['vendedor_codigo']?.toString(),
    'vendedor_nome': pedido['vendedor_nome']?.toString(),
    'cliente_id': (pedido['cliente_id'] is int) ? pedido['cliente_id'] : null,
    'cliente_nome': pedido['cliente_nome']?.toString(),
    'assinatura': _bytesToHex0x(pedido['assinatura']),       // legado (mantido)
    'assinatura_path': pedido['assinatura_path']?.toString(),// ✅ NOVO: caminho do arquivo
    'cliente_telefone': pedido['cliente_telefone']?.toString(),
    'cliente_endereco': pedido['cliente_endereco']?.toString(),
    'cliente_cidade': pedido['cliente_cidade']?.toString(),
    'cliente_cpf_cnpj': pedido['cliente_cpf_cnpj']?.toString(),
    'cliente_insc_estadual': pedido['cliente_insc_estadual']?.toString(),
    'cliente_cep': pedido['cliente_cep']?.toString(),
    'cliente_anotacao': pedido['cliente_anotacao']?.toString(),
    'cliente_nome_fantasia': pedido['cliente_nome_fantasia']?.toString(),
    'cliente_whatsapp': pedido['cliente_whatsapp']?.toString(),
    'cliente_email': pedido['cliente_email']?.toString(),
  };

  // Define o id do registro local.
  // - Se o pedido já tem id (ex.: veio do servidor), respeita-o.
  // - Se é um pedido novo, usa um id na faixa local segura (>= kLocalIdBase),
  //   reaproveitando o id de uma linha de mesmo (numero, vendedor) que nunca
  //   chegou ao servidor (rascunho so_local, ou salvo/pendente na faixa
  //   local), para não trocar o id a cada novo salvamento.
  // - Se o (numero, vendedor) é de outra linha que não pode ser reaproveitada
  //   (pedido já enviado), lança [NumeroEmUso] ANTES de escrever: o
  //   `INSERT OR REPLACE` pelo índice único local apagaria aquele pedido.
  final numero = map['numero'] as String?;
  final vend = map['vendedor_codigo'] as String?;
  final int? idExistente = (pedido['id'] is int)
      ? pedido['id'] as int
      : int.tryParse('${pedido['id'] ?? ''}');
  if (idExistente != null) {
    map['id'] = await _idDaGravacao(db, idExistente, numero, vend, pedido['id_aparelho']);
  } else {
    int? reusar;
    final ex = await _outraComMesmoNumero(db, numero, vend, null);
    if (ex != null) {
      if (!_reaproveitavel(ex)) throw NumeroEmUso(numero!, vend!);
      reusar = (ex['id'] as num).toInt();
    }
    map['id'] = reusar ?? await proximoIdLocalSeguro(db);
  }

  await _aplicarCamposLocais(db, map, pedido, replace: true);
  await _insertOrReplaceFiltered(db, 'pedidos', map);
  return map['id'] as int;
}

/// Atualiza o pedido e devolve o id da linha gravada (pode ser outro que o
/// do mapa: veja [_idDaGravacao]).
Future<int> atualizarPedidoLocal(Map<String, dynamic> pedido) async {
  final db = await getDb();
  final idMapa = pedido['id'];
  if (idMapa == null) return salvarPedidoLocal(pedido);
  final idPedido = idMapa is int ? idMapa : int.tryParse('$idMapa');
  if (idPedido == null) return salvarPedidoLocal({...pedido, 'id': null});

  final map = <String, dynamic>{
    'numero': pedido['numero']?.toString(),
    'produtos': _ensureProdutosJson(pedido['produtos']),
    'total': (pedido['total'] is num) ? (pedido['total'] as num).toDouble() : 0.0,
    'status': (pedido['status'] ?? 'salvo').toString(),
    'datahora': (pedido['datahora'] is String && (pedido['datahora'] as String).isNotEmpty)
        ? pedido['datahora']
        : DateTime.now().toUtc().toIso8601String(),
    'vendedor_codigo': pedido['vendedor_codigo']?.toString(),
    'vendedor_nome': pedido['vendedor_nome']?.toString(),
    'cliente_id': (pedido['cliente_id'] is int) ? pedido['cliente_id'] : null,
    'cliente_nome': pedido['cliente_nome']?.toString(),
    'assinatura': _bytesToHex0x(pedido['assinatura']),       // legado
    'assinatura_path': pedido['assinatura_path']?.toString(),// ✅ NOVO
    'cliente_telefone': pedido['cliente_telefone']?.toString(),
    'cliente_endereco': pedido['cliente_endereco']?.toString(),
    'cliente_cidade': pedido['cliente_cidade']?.toString(),
    'cliente_cpf_cnpj': pedido['cliente_cpf_cnpj']?.toString(),
    'cliente_insc_estadual': pedido['cliente_insc_estadual']?.toString(),
    'cliente_cep': pedido['cliente_cep']?.toString(),
    'cliente_anotacao': pedido['cliente_anotacao']?.toString(),
    'cliente_nome_fantasia': pedido['cliente_nome_fantasia']?.toString(),
    'cliente_whatsapp': pedido['cliente_whatsapp']?.toString(),
    'cliente_email': pedido['cliente_email']?.toString(),
  };

  // Trocar o número para o de outra linha apagaria a outra (índice único);
  // o mesmo pedido já trocado de id pelo eco é seguido.
  final id = await _idDaGravacao(db, idPedido, map['numero'] as String?,
      map['vendedor_codigo'] as String?, pedido['id_aparelho']);
  map['id'] = id;
  await _aplicarCamposLocais(db, map, pedido, replace: false);
  map.remove('id');
  final filtered = await _filterToTableColumns(db, 'pedidos', map);
  final n = await db.update(
    'pedidos',
    filtered,
    where: 'id = ?',
    whereArgs: [id],
    conflictAlgorithm: sq.ConflictAlgorithm.replace,
  );
  // Nunca dá a gravação por feita quando nada foi escrito.
  if (n == 0) throw StateError('Pedido $id não existe mais no aparelho; nada foi gravado.');
  return id;
}

Future<List<Map<String, dynamic>>> listarPedidosLocais() async {
  final db = await getDb();
  return db.query('pedidos', orderBy: 'datetime(datahora) DESC, id DESC');
}

/// 🔹 Somente pedidos do vendedor (para telas filtradas por login)
Future<List<Map<String, dynamic>>> listarPedidosLocaisPorVendedor(
    String vendedorCodigo, {
      String? status, // opcional: 'salvo' | 'finalizado'
    }) async {
  final db = await getDb();
  if (status == null) {
    return db.query(
      'pedidos',
      where: 'vendedor_codigo = ?',
      whereArgs: [vendedorCodigo],
      orderBy: 'datetime(datahora) DESC, id DESC',
    );
  } else {
    return db.query(
      'pedidos',
      where: 'vendedor_codigo = ? AND status = ?',
      whereArgs: [vendedorCodigo, status],
      orderBy: 'datetime(datahora) DESC, id DESC',
    );
  }
}

/// Pedidos do vendedor com um status exato ('salvo' | 'finalizado' | 'cancelado').
Future<List<Map<String, dynamic>>> listarPedidosLocaisPorStatus(
    String vendedorCodigo, String status) {
  return listarPedidosLocaisPorVendedor(vendedorCodigo, status: status);
}

/// Pedidos que ainda precisam ser enviados ao servidor.
Future<List<Map<String, dynamic>>> listarPedidosPendentesEnvio(String vendedorCodigo) async {
  final db = await getDb();
  return db.query(
    'pedidos',
    where: 'pendente_envio = 1 AND vendedor_codigo = ?',
    whereArgs: [vendedorCodigo],
    orderBy: 'datetime(datahora) ASC',
  );
}

Future<int> contarPedidosPendentesEnvio(String vendedorCodigo) async {
  final db = await getDb();
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM pedidos WHERE pendente_envio = 1 AND vendedor_codigo = ?',
    [vendedorCodigo],
  );
  return sq.Sqflite.firstIntValue(r) ?? 0;
}

/// Códigos de vendedores que têm pedidos aguardando envio.
Future<Set<String>> codigosComPendentesEnvio() async {
  final db = await getDb();
  final r = await db.rawQuery(
    'SELECT DISTINCT vendedor_codigo AS c FROM pedidos '
    'WHERE pendente_envio = 1 AND vendedor_codigo IS NOT NULL',
  );
  return r.map((e) => e['c'].toString()).toSet();
}

/// Muda status do pedido
Future<int> atualizarStatusPedido(int id, String status) async {
  final db = await getDb();
  return db.update('pedidos', {'status': status}, where: 'id = ?', whereArgs: [id]);
}

/// Excluir pedido (para botão "Apagar")
Future<int> apagarPedidoLocal(int id) async {
  final db = await getDb();
  return db.delete('pedidos', where: 'id = ?', whereArgs: [id]);
}

/// `true` se alguma linha do aparelho (fora a de [ignorarId], o próprio
/// pedido) já tem esse `(numero, vendedor_codigo)`.
Future<bool> numeroUsadoNoAparelho(String numero, String vendedorCodigo,
    {int? ignorarId}) async {
  final db = await getDb();
  return await _outraComMesmoNumero(db, numero, vendedorCodigo, ignorarId) != null;
}

/// Busca o maior número numérico de pedido (campo texto).
Future<int?> buscarUltimoNumeroPedido() async {
  final db = await getDb();
  final rows = await db.query('pedidos', columns: ['numero']);
  int? maxN;
  for (final r in rows) {
    final s = (r['numero'] ?? '').toString().trim();
    final n = int.tryParse(s);
    if (n != null) {
      if (maxN == null || n > maxN) maxN = n;
    }
  }
  return maxN;
}

/// -------- Consultas de apoio (recência de clientes) --------

Future<DateTime?> getUltimoPedidoCliente(int clienteId) async {
  final db = await getDb();
  final r = await db.rawQuery('''
    SELECT MAX(datahora) AS last_date
    FROM pedidos
    WHERE cliente_id = ?
  ''', [clienteId]);

  final s = (r.isNotEmpty ? r.first['last_date'] : null) as String?;
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s).toUtc();
  } catch (_) {
    return null;
  }
}

Future<Map<int, DateTime?>> getUltimoPedidoPorCliente() async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT cliente_id, MAX(datahora) AS last_date
    FROM pedidos
    WHERE cliente_id IS NOT NULL
    GROUP BY cliente_id
  ''');

  final out = <int, DateTime?>{};
  for (final r in rows) {
    final id = r['cliente_id'] as int?;
    final s = r['last_date'] as String?;
    if (id == null) continue;
    if (s == null || s.isEmpty) {
      out[id] = null;
    } else {
      try {
        out[id] = DateTime.parse(s).toUtc();
      } catch (_) {
        out[id] = null;
      }
    }
  }
  return out;
}

/// Remove duplicados de pedidos mantendo o mais novo (maior id)
/// Apenas quando ambos (numero, vendedor_codigo) não são nulos/nem vazios.
Future<void> _dedupPedidosByNumeroVendedor(sq.Database db) async {
  try {
    await db.execute('''
      DELETE FROM pedidos
      WHERE numero IS NOT NULL AND numero <> ''
        AND vendedor_codigo IS NOT NULL AND vendedor_codigo <> ''
        AND id NOT IN (
          SELECT MAX(id) FROM pedidos
          WHERE numero IS NOT NULL AND numero <> ''
            AND vendedor_codigo IS NOT NULL AND vendedor_codigo <> ''
          GROUP BY numero, vendedor_codigo
        );
    ''');
    debugPrint('Deduplicação de pedidos concluída antes do índice único.');
  } catch (e) {
    debugPrint('Falha ao deduplicar pedidos: $e');
  }
}
