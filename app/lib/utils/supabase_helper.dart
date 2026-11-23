// lib/utils/supabase_helper.dart
//
// - Insere/atualiza no SQLite via transaction + batch (rápido e seguro)
// - Normaliza assinatura (bytes/base64/hex) usando convert.dart
// - Garante cliente no Supabase (ensureClienteSupabaseId) antes de salvar pedido
// - Envio ao Supabase com UPSERT (numero,vendedor_codigo) quando disponível; se não, fallback:
//     * tenta localizar por (numero,vendedor_codigo) e faz UPDATE por id
//     * senão, INSERT normal.
// - Ao receber do Supabase, aplica no SQLite com REPLACE e faz limpeza local para evitar duplicação.
// - ***Preserva sempre `assinatura_path` no SQLite local***.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'convert.dart'; // assinaturaToBytes(), bytesToHex0x()
import 'db.dart';      // getDb()
import 'id_aparelho.dart'; // novoIdAparelho()

final supabase = Supabase.instance.client;

// ---------------------- Utils de conversão ----------------------

/// Converte qualquer entrada de assinatura (bytes/base64/hex) para HEX "0x..."
String? _toHex0x(dynamic any) {
  final bytes = assinaturaToBytes(any);
  return bytes == null ? null : bytesToHex0x(bytes);
}

/// Converte qualquer entrada de assinatura (bytes/base64/hex) para base64 (sem data URI)
String? _toBase64(dynamic any) {
  final bytes = assinaturaToBytes(any);
  return bytes == null ? null : base64Encode(bytes);
}

/// Remove chaves com valor `null` (limpa payloads)
Map<String, dynamic> _stripNulls(Map<String, dynamic> m) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    if (v != null) out[k] = v;
  });
  return out;
}

// ---------------------- Trava de pedidos ----------------------

Future<void> _filaPedidos = Future<void>.value();
final Object _dentroDaTrava = Object();

/// Roda [acao] sozinha: envio de pendentes e gravação/envio de pedido nunca
/// correm ao mesmo tempo (senão o eco antigo do servidor sobrescreve uma edição
/// mais nova e limpa o `pendente_envio` dela). Chamadas aninhadas na mesma
/// cadeia (ex.: `subirPedidosPendentes` -> `salvarPedidoSupabase`) não esperam
/// por si mesmas.
Future<T> comTravaDePedidos<T>(Future<T> Function() acao) {
  if (Zone.current[_dentroDaTrava] == true) return acao();
  final anterior = _filaPedidos;
  final liberar = Completer<void>();
  _filaPedidos = liberar.future;
  return anterior
      .then((_) => runZoned(acao, zoneValues: {_dentroDaTrava: true}))
      .whenComplete(liberar.complete);
}

// ---------------------- Sincronização geral ----------------------

/// Há internet? (resolução de DNS simples)
Future<bool> temInternet() async {
  try {
    final result = await InternetAddress.lookup('example.com');
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

const String _keyUltimaSync = 'ultima_sincronizacao';

/// `true` se nunca sincronizou ou a última sync completa tem 7 dias ou mais.
Future<bool> syncVencida() async {
  final prefs = await SharedPreferences.getInstance();
  final ultima = prefs.getInt(_keyUltimaSync);
  if (ultima == null) return true;
  final desde = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ultima));
  return desde >= const Duration(days: 7);
}

/// [sincronizarTudo] e, só se deu certo, grava a data da última sync.
Future<bool> sincronizarTudoERegistrar({required String vendedorCodigo}) async {
  final ok = await sincronizarTudo(vendedorCodigo: vendedorCodigo);
  if (ok) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUltimaSync, DateTime.now().millisecondsSinceEpoch);
  }
  return ok;
}

/// Sync completa do vendedor logado: baixa clientes, produtos e os pedidos
/// dele, depois tenta subir os pedidos que aguardam envio.
/// Devolve `true` se os downloads deram certo; falhas de envio continuam
/// visíveis pelo contador de pendentes (`contarPedidosPendentesEnvio`).
Future<bool> sincronizarTudo({required String vendedorCodigo}) async {
  var ok = true;
  for (final passo in <Future<void> Function()>[
    sincronizarClientes,
    sincronizarProdutos,
    () => sincronizarPedidos(vendedorCodigo: vendedorCodigo),
  ]) {
    try {
      await passo();
    } catch (_) {
      ok = false; // o passo já registrou o erro
    }
  }
  try {
    final r = await subirPedidosPendentes(vendedorCodigo: vendedorCodigo);
    // ignore: avoid_print
    print('📤 Pendentes: ${r.enviados} enviados, ${r.falhas} falhas, '
        '${r.numeroEmUso} com número em uso');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao subir pendentes: $e');
  }
  return ok;
}

// ---------------------- CLIENTES ----------------------

Future<void> sincronizarClientes() async {
  try {
    final response = await supabase.from('clientes').select('*');
    final List<dynamic> clientes = response;

    final db = await getDb();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final raw in clientes) {
        final c = Map<String, dynamic>.from(raw as Map);
        final map = <String, dynamic>{
          'id': c['id'],
          'nome': c['nome'],
          'nome_fantasia': c['nome_fantasia'], // pode vir null (ok)
          'cpf_cnpj': c['cpf_cnpj'],
          'telefone': c['telefone'],
          'whatsapp': c['whatsapp'],           // pode vir null (ok)
          'email': c['email'],                 // pode vir null (ok)
          'endereco': c['endereco'],
          'cidade': c['cidade'],
          'anotacao': c['anotacao'],
          'ativo': (c['ativo'] is bool)
              ? (c['ativo'] == true ? 1 : 0)
              : (c['ativo'] is int ? c['ativo'] : 1),
          'datahora': c['datahora'],
          'insc_estadual': c['insc_estadual'],
          'cep': c['cep'],
        };
        batch.insert('clientes', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    // ignore: avoid_print
    print('🟢 Clientes sincronizados (${clientes.length})');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar clientes: $e');
    rethrow;
  }
}

Future<void> inserirClienteSupabase(Map<String, dynamic> cliente) async {
  try {
    await supabase.from('clientes').insert(_stripNulls(cliente));
    // ignore: avoid_print
    print('✅ Cliente enviado ao Supabase');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao enviar cliente: $e');
  }
}

// ---------------------- PRODUTOS ----------------------

Future<void> sincronizarProdutos() async {
  try {
    // '*' evita erro se seu Supabase não tiver 'codigo' e 'unidade'
    final response = await supabase.from('produtos').select('*');
    final List<dynamic> produtos = response;

    final db = await getDb();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final raw in produtos) {
        final p = Map<String, dynamic>.from(raw as Map);

        final preco = p['preco'];
        double precoOk = 0.0;
        if (preco is num) {
          precoOk = preco.toDouble();
        } else if (preco is String) {
          precoOk = double.tryParse(preco.replaceAll(',', '.')) ?? 0.0;
        }

        final map = <String, dynamic>{
          'id': p['id'],
          'codigo': p['codigo'],       // pode ser null (ok)
          'nome': p['nome'],
          'unidade': p['unidade'],     // pode ser null (ok)
          'preco': precoOk,
          'ativo': (p['ativo'] is bool)
              ? (p['ativo'] == true ? 1 : 0)
              : (p['ativo'] is int ? p['ativo'] : 1),
        };
        batch.insert('produtos', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    // ignore: avoid_print
    print('🟢 Produtos sincronizados (${produtos.length})');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar produtos: $e');
    rethrow;
  }
}

// ---------------------- PEDIDOS ----------------------

/// Baixa só os pedidos do vendedor (o RLS já filtra; o app filtra também).
/// Roda sob [comTravaDePedidos]: a foto baixada não pode cair por cima de um
/// envio que terminou depois dela.
Future<void> sincronizarPedidos({required String vendedorCodigo}) =>
    comTravaDePedidos(() => _sincronizarPedidos(vendedorCodigo));

Future<void> _sincronizarPedidos(String vendedorCodigo) async {
  try {
    final response =
        await supabase.from('pedidos').select('*').eq('vendedor_codigo', vendedorCodigo);
    final pedidos = [
      for (final raw in response) Map<String, dynamic>.from(raw),
    ];
    await aplicarPedidosRemotos(pedidos);

    // ignore: avoid_print
    print('🟢 Pedidos sincronizados (${pedidos.length})');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar pedidos: $e');
    rethrow;
  }
}

//// Colunas de auditoria que só o servidor preenche. O app guarda uma cópia em
/// texto (vinda do eco/sync) e nunca as envia.
const List<String> _colunasAuditoria = [
  'enviado_em',
  'alterado_em',
  'finalizado_em',
  'finalizado_por',
  'finalizado_manual',
  'cancelado_em',
  'cancelado_por',
];

/// `finalizado_manual` guardado como texto: 'true' / 'false' (ou null).
String? _boolComoTexto(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v.toString();
  final s = '$v'.trim().toLowerCase();
  if (s == 'true' || s == 't' || s == '1') return 'true';
  if (s == 'false' || s == 'f' || s == '0') return 'false';
  return '$v';
}

String? _texto(dynamic v) {
  final s = v?.toString();
  return (s == null || s.isEmpty) ? null : s;
}

/// id_aparelho e cópias de auditoria de uma linha do servidor, para o SQLite.
/// Sem id_aparelho no servidor, fica [idAparelhoLocal] (o que o aparelho já
/// tinha). Linha do servidor nunca é rascunho local nem tem erro de envio.
Map<String, dynamic> _camposDoServidor(
        Map<String, dynamic> remoto, String? idAparelhoLocal) =>
    {
      'id_aparelho': _texto(remoto['id_aparelho']) ?? _texto(idAparelhoLocal),
      'so_local': 0,
      'erro_envio': null,
      for (final c in _colunasAuditoria)
        c: c == 'finalizado_manual' ? _boolComoTexto(remoto[c]) : _texto(remoto[c]),
    };

/// Aplica no SQLite os pedidos vindos do servidor.
/// - Pula o remoto se há pedido local aguardando envio (`pendente_envio = 1`)
///   ou rascunho antigo só do aparelho (`so_local = 1`) com o mesmo `id` ou o
///   mesmo `(numero, vendedor_codigo)`: a versão local vence, e o índice único
///   (numero, vendedor_codigo) não pode apagá-la no `INSERT OR REPLACE`.
/// - Um local `salvo` com o mesmo id **e** o mesmo (numero, vendedor_codigo)
///   é o próprio pedido (aberto, já enviado) e é substituído pela versão do
///   servidor. Com o mesmo id e outro (numero, vendedor_codigo) é outro
///   pedido: é realocado para a faixa local segura antes do `INSERT OR REPLACE`.
/// - Mantém o `id_aparelho` local quando o servidor não tem um.
Future<void> aplicarPedidosRemotos(List<Map<String, dynamic>> remotos) async {
  final db = await getDb();
  await db.transaction((txn) async {
    final aplicar = <(Map<String, dynamic>, String?)>[];
    for (final m in remotos) {
      final rid =
          (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id'] ?? ''}');
      final numero = m['numero']?.toString();
      final vend = m['vendedor_codigo']?.toString();

      final protegido = await txn.query(
        'pedidos',
        columns: ['id'],
        where: '(pendente_envio = 1 OR so_local = 1) '
            'AND (id = ? OR (numero = ? AND vendedor_codigo = ?))',
        whereArgs: [rid, numero, vend],
        limit: 1,
      );
      if (protegido.isNotEmpty) continue;

      String? idAparelhoLocal;

      // 🛡️ Protege rascunhos locais: se o remoto traz um id que colide com um
      // `salvo` local de OUTRO pedido (outro numero/vendedor), realoca o local
      // para a faixa de id segura ANTES de aplicar. Sem isso, o
      // `INSERT OR REPLACE` abaixo o apagaria.
      if (rid != null) {
        final col = await txn.query(
          'pedidos',
          columns: ['id', 'status', 'numero', 'vendedor_codigo', 'id_aparelho'],
          where: 'id = ?',
          whereArgs: [rid],
          limit: 1,
        );
        if (col.isNotEmpty) {
          final l = col.first;
          final mesmoPedido = l['numero']?.toString() == numero &&
              l['vendedor_codigo']?.toString() == vend;
          if (l['status']?.toString() == 'salvo' && !mesmoPedido) {
            final novoId = await proximoIdLocalSeguro(txn);
            await txn.update('pedidos', {'id': novoId},
                where: 'id = ?', whereArgs: [rid]);
          } else {
            idAparelhoLocal = _texto(l['id_aparelho']);
          }
        }
      }
      if (idAparelhoLocal == null && numero != null && vend != null) {
        final porNumero = await txn.query(
          'pedidos',
          columns: ['id_aparelho'],
          where: 'numero = ? AND vendedor_codigo = ?',
          whereArgs: [numero, vend],
          limit: 1,
        );
        if (porNumero.isNotEmpty) {
          idAparelhoLocal = _texto(porNumero.first['id_aparelho']);
        }
      }
      aplicar.add((m, idAparelhoLocal));
    }

    final batch = txn.batch();
    for (final (ped, idAparelhoLocal) in aplicar) {
      final produtosLocal = (ped['produtos'] is String)
          ? ped['produtos']
          : jsonEncode(ped['produtos'] ?? []);

      final assinaturaHex = _toHex0x(ped['assinatura']);

      final map = <String, dynamic>{
        'id': ped['id'],
        'numero': ped['numero']?.toString(), // pode não existir no Supabase (ok => null)
        'produtos': produtosLocal,
        'total': (ped['total'] is num)
            ? (ped['total'] as num).toDouble()
            : double.tryParse('${ped['total']}') ?? 0.0,
        'status': (ped['status'] ?? 'salvo').toString(),
        'datahora': ped['datahora'],
        'vendedor_codigo': ped['vendedor_codigo']?.toString(),
        'vendedor_nome': ped['vendedor_nome']?.toString(),
        'cliente_id': (ped['cliente_id'] is int) ? ped['cliente_id'] : null,
        'cliente_nome': ped['cliente_nome']?.toString(),
        'assinatura': assinaturaHex,
        'cliente_telefone': ped['cliente_telefone']?.toString(),
        'cliente_endereco': ped['cliente_endereco']?.toString(),
        'cliente_cidade': ped['cliente_cidade']?.toString(),
        'cliente_cpf_cnpj': ped['cliente_cpf_cnpj']?.toString(),
        'cliente_insc_estadual': ped['cliente_insc_estadual']?.toString(),
        'cliente_cep': ped['cliente_cep']?.toString(),
        'cliente_anotacao': ped['cliente_anotacao']?.toString(),
        // Os três abaixo podem não existir no servidor; manteremos só localmente se houver.
        'cliente_nome_fantasia': ped['cliente_nome_fantasia']?.toString(),
        'cliente_whatsapp': ped['cliente_whatsapp']?.toString(),
        'cliente_email': ped['cliente_email']?.toString(),
        // Veio do servidor: não está aguardando envio.
        'pendente_envio': 0,
        // id_aparelho, so_local = 0, erro_envio = null e cópias de auditoria.
        ..._camposDoServidor(ped, idAparelhoLocal),
        // `assinatura_path` não existe no servidor; ficará null ao sincronizar tudo.
      };

      batch.insert('pedidos', map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  });
}

/// Sobe os pedidos do vendedor que ainda aguardam envio (`pendente_envio = 1`,
/// qualquer situação). Cada falha deixa o pedido pendente e segue para o
/// próximo. Pedido com `erro_envio = 'numero'` (o número já é de outro pedido
/// no servidor) não é tentado: continua pendente e conta em `numeroEmUso` até
/// o vendedor trocar o número. Chamar ao abrir com internet, depois do login e
/// depois da sync. Roda sob [comTravaDePedidos].
Future<({int enviados, int falhas, int numeroEmUso})> subirPedidosPendentes({
  required String vendedorCodigo,
  Future<void> Function(Map<String, dynamic>) enviar = salvarPedidoSupabase,
}) =>
    comTravaDePedidos(() => _subirPedidosPendentes(vendedorCodigo, enviar));

Future<({int enviados, int falhas, int numeroEmUso})> _subirPedidosPendentes(
  String vendedorCodigo,
  Future<void> Function(Map<String, dynamic>) enviar,
) async {
  final rows = await listarPedidosPendentesEnvio(vendedorCodigo);
  var enviados = 0;
  var falhas = 0;
  var numeroEmUso = 0;
  for (final row in rows) {
    if (row['vendedor_codigo']?.toString() != vendedorCodigo) continue;
    if (row['erro_envio']?.toString() == kErroNumeroEmUso) {
      numeroEmUso++;
      continue;
    }
    try {
      await enviar(Map<String, dynamic>.from(row));
      enviados++;
    } on NumeroEmUso {
      numeroEmUso++;
      await _marcarNumeroEmUso(row);
    } catch (e) {
      falhas++;
      // ignore: avoid_print
      print('⚠️ Falha ao subir pendente ${row['numero'] ?? row['id']}: $e');
    }
  }
  return (enviados: enviados, falhas: falhas, numeroEmUso: numeroEmUso);
}

// Apaga duplicados locais após salvar no servidor:
/// - Remove o registro local antigo (idLocalAntigo)
/// - Remove qualquer outro com o mesmo (numero, vendedor_codigo) e id != idNovo
Future<void> _limparDuplicadosLocais({
  required DatabaseExecutor txn,
  required Map<String, dynamic> remoto,
  int? idLocalAntigo,
}) async {
  final idNovo = (remoto['id'] is int)
      ? (remoto['id'] as int)
      : int.tryParse('${remoto['id']}') ?? -1;

  final numero = (remoto['numero'] ?? '').toString();
  final vend = (remoto['vendedor_codigo'] ?? '').toString();
  final temNumero = numero.isNotEmpty;

  // 1) remove o id antigo se existir e for diferente
  if (idLocalAntigo != null && idLocalAntigo != idNovo && idLocalAntigo > 0) {
    await txn.delete('pedidos', where: 'id = ?', whereArgs: [idLocalAntigo]);
  }

  // 2) remove outros com mesma chave (numero + vendedor) e id diferente do novo
  if (temNumero) {
    if (vend.isEmpty) {
      await txn.delete(
        'pedidos',
        where: 'numero = ? AND vendedor_codigo IS NULL AND id <> ?',
        whereArgs: [numero, idNovo],
      );
    } else {
      await txn.delete(
        'pedidos',
        where: 'numero = ? AND vendedor_codigo = ? AND id <> ?',
        whereArgs: [numero, vend, idNovo],
      );
    }
  }
}

// ---------------------- Garantia de cliente (FK) ----------------------

/// Garante que exista um cliente correspondente no Supabase e retorna o id remoto.
/// Regras/ordem:
/// 1) Se pedido['cliente_id'] já existir no Supabase, usa ele.
/// 2) Senão tenta achar por cpf_cnpj.
/// 3) Senão tenta (nome + telefone).
/// 4) Não achou? INSERE usando apenas colunas do seu schema `clientes`.
Future<int> ensureClienteSupabaseId(Map<String, dynamic> pedido) async {
  final c = Supabase.instance.client;

  int? idPedido = (pedido['cliente_id'] as num?)?.toInt();
  final String cpf = (pedido['cliente_cpf_cnpj'] ?? '').toString().trim();
  final String nome = (pedido['cliente_nome'] ?? '').toString().trim();
  final String telefone = (pedido['cliente_telefone'] ?? '').toString().trim();

  // 1) Já tem id? Confere se existe no Supabase.
  if (idPedido != null) {
    final exist = await c.from('clientes').select('id').eq('id', idPedido).maybeSingle();
    if (exist != null && exist['id'] != null) {
      return (exist['id'] as num).toInt();
    }
  }

  // 2) Procura por CPF/CNPJ
  if (cpf.isNotEmpty) {
    final byCpf = await c.from('clientes').select('id').eq('cpf_cnpj', cpf).maybeSingle();
    if (byCpf != null && byCpf['id'] != null) {
      return (byCpf['id'] as num).toInt();
    }
  }

  // 3) Procura por (nome + telefone)
  if (nome.isNotEmpty && telefone.isNotEmpty) {
    final list = await c.from('clientes').select('id').eq('nome', nome).eq('telefone', telefone);
    if (list is List && list.isNotEmpty && list.first['id'] != null) {
      return (list.first['id'] as num).toInt();
    }
  }

  // 4) Insere um novo cliente (somente colunas existentes no seu schema)
  final insertData = {
    'nome': nome.isEmpty ? 'Cliente' : nome,
    'cpf_cnpj': cpf.isEmpty ? null : cpf,
    'telefone': telefone.isEmpty ? null : telefone,
    'endereco': (pedido['cliente_endereco'] ?? '').toString().trim().isEmpty
        ? null
        : pedido['cliente_endereco'].toString(),
    'cidade': (pedido['cliente_cidade'] ?? '').toString().trim().isEmpty
        ? null
        : pedido['cliente_cidade'].toString(),
    'anotacao': (pedido['cliente_anotacao'] ?? '').toString().trim().isNotEmpty
        ? pedido['cliente_anotacao'].toString()
        : null,
    'ativo': true,
    'datahora': DateTime.now().toUtc().toIso8601String(),
    'insc_estadual': (pedido['cliente_insc_estadual'] ?? '').toString().trim().isNotEmpty
        ? pedido['cliente_insc_estadual'].toString()
        : null,
    'cep': (pedido['cliente_cep'] ?? '').toString().trim().isNotEmpty
        ? pedido['cliente_cep'].toString()
        : null,
  };

  final inserted = await c.from('clientes').insert(_stripNulls(insertData)).select('id').single();
  return (inserted['id'] as num).toInt();
}

/// ---------------------- Conflito de número ----------------------

/// Valor de `erro_envio` quando o número já é de outro pedido no servidor.
const String kErroNumeroEmUso = 'numero';

/// O servidor já tem o mesmo `(numero, vendedor_codigo)` com outro
/// `id_aparelho`: é outro pedido (de outro aparelho do mesmo vendedor). O
/// envio não acontece; o pedido fica pendente até o vendedor trocar o número.
class NumeroEmUso implements Exception {
  const NumeroEmUso(this.numero, this.vendedorCodigo);
  final String numero;
  final String vendedorCodigo;

  @override
  String toString() => 'NumeroEmUso: o pedido $numero do vendedor $vendedorCodigo '
      'já existe no servidor com outro id_aparelho';
}

/// `true` só quando os dois id_aparelho existem e são diferentes.
/// - Local sem id_aparelho (pedido legado): comportamento de hoje, sem conflito.
/// - Remoto sem id_aparelho (pedido antigo, ou o próprio pedido enviado pelo
///   APK antigo): segue o upsert como hoje.
bool conflitoDeNumero(String? idAparelhoLocal, String? idAparelhoRemoto) {
  final l = idAparelhoLocal?.trim() ?? '';
  final r = idAparelhoRemoto?.trim() ?? '';
  if (l.isEmpty || r.isEmpty) return false;
  return l != r;
}

Future<Map<String, dynamic>?> _buscarRemotoPorNumeroSupabase(
    String numero, String vendedorCodigo) async {
  final r = await supabase
      .from('pedidos')
      .select('id, id_aparelho')
      .eq('numero', numero)
      .eq('vendedor_codigo', vendedorCodigo)
      .maybeSingle();
  return r == null ? null : Map<String, dynamic>.from(r);
}

/// Busca `id, id_aparelho` do pedido do servidor com esse
/// `(numero, vendedor_codigo)`, ou null se não existe. Lança se não houver
/// rede. Trocável nos testes.
@visibleForTesting
Future<Map<String, dynamic>?> Function(String numero, String vendedorCodigo)
    buscarRemotoPorNumero = _buscarRemotoPorNumeroSupabase;

/// `true` se nenhum pedido do servidor tem esse `(numero, vendedor_codigo)`.
/// Sem rede (ou qualquer erro) devolve `true`: offline não bloqueia salvar; o
/// conflito, se houver, aparece no envio ([NumeroEmUso]).
Future<bool> numeroLivreNoServidor(String numero, String vendedorCodigo) async {
  try {
    return await buscarRemotoPorNumero(numero, vendedorCodigo) == null;
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Não deu para conferir o número $numero no servidor: $e');
    return true;
  }
}

/// Persiste `erro_envio = 'numero'` (e mantém pendente) na linha local do
/// pedido, desde que o número ainda seja o que foi enviado.
Future<void> _marcarNumeroEmUso(Map<String, dynamic> pedido) async {
  final db = await getDb();
  final id = _idDe(pedido);
  final numero = pedido['numero']?.toString();
  final vend = pedido['vendedor_codigo']?.toString();
  final valores = {'erro_envio': kErroNumeroEmUso, 'pendente_envio': 1};
  if (id != null) {
    await db.update('pedidos', valores,
        where: 'id = ? AND numero = ?', whereArgs: [id, numero]);
  } else {
    await db.update('pedidos', valores,
        where: 'numero = ? AND vendedor_codigo = ?', whereArgs: [numero, vend]);
  }
}

int? _idDe(Map<String, dynamic> pedido) {
  final raw = pedido['id'];
  return raw is int ? raw : int.tryParse('${raw ?? ''}');
}

/// Pedido sem id_aparelho (pendente da v16): gera um, grava no SQLite e só
/// então devolve o pedido com ele, para o envio levar o mesmo valor que fica
/// no aparelho. Se o SQLite já tinha um, usa o guardado.
Future<Map<String, dynamic>> _garantirIdAparelho(Map<String, dynamic> pedido) async {
  if (_texto(pedido['id_aparelho']) != null) return pedido;
  final db = await getDb();
  final novo = novoIdAparelho();
  final id = _idDe(pedido);
  final String where;
  final List<Object?> args;
  if (id != null) {
    where = 'id = ?';
    args = [id];
  } else {
    where = 'numero = ? AND vendedor_codigo = ?';
    args = [pedido['numero']?.toString(), pedido['vendedor_codigo']?.toString()];
  }
  await db.update('pedidos', {'id_aparelho': novo},
      where: "$where AND (id_aparelho IS NULL OR id_aparelho = '')", whereArgs: args);
  final r = await db.query('pedidos',
      columns: ['id_aparelho'], where: where, whereArgs: args, limit: 1);
  final guardado = r.isEmpty ? null : _texto(r.first['id_aparelho']);
  return {...pedido, 'id_aparelho': guardado ?? novo};
}

// ---------------------- Salvar pedido (com FK garantida) ----------------------

/// Campos que nunca vão ao servidor: controle local, colunas que o servidor
/// não tem, e as de auditoria (o servidor é quem preenche).
const List<String> _camposForaDoPayload = [
  'id', // id é do servidor
  'cliente_nome_fantasia',
  'cliente_whatsapp',
  'cliente_email',
  'assinatura_path', // caminho local da assinatura
  'pendente_envio',
  'so_local',
  'erro_envio',
  ..._colunasAuditoria,
];

/// Monta o payload do pedido para o servidor a partir do mapa local (tela ou
/// linha do SQLite). Leva `id_aparelho` e `status` como estão (salvo,
/// cancelado ou finalizado). `cliente_id` é trocado pelo id remoto no envio.
Map<String, dynamic> montarPayloadPedido(Map<String, dynamic> pedido) {
  final ped = <String, dynamic>{...pedido};
  for (final c in _camposForaDoPayload) {
    ped.remove(c);
  }

  // produtos: lista JSON (jsonb). A linha do SQLite guarda texto JSON.
  final produtos = ped['produtos'];
  if (produtos is String) {
    try {
      final d = jsonDecode(produtos);
      ped['produtos'] = d is List ? d : [];
    } catch (_) {
      ped['produtos'] = [];
    }
  } else if (produtos is! List) {
    ped['produtos'] = [];
  }

  // assinatura → base64 (bytea) se houver
  final assinaturaB64 = _toBase64(ped['assinatura']);
  if (assinaturaB64 != null) {
    ped['assinatura'] = assinaturaB64;
  } else {
    ped.remove('assinatura');
  }

  // datahora ISO-8601 UTC
  if (ped['datahora'] is DateTime) {
    ped['datahora'] = (ped['datahora'] as DateTime).toUtc().toIso8601String();
  }
  return ped;
}

/// Grava o payload no Supabase e devolve a linha resultante (o eco), ou null.
/// - Garante o cliente (FK) e usa o id remoto dele.
/// - Se o Supabase tiver `numero` + índice único com `vendedor_codigo`, usa UPSERT
/// - Se NÃO tiver, tenta localizar por (numero,vendedor_codigo) e faz UPDATE por id; se não achar, INSERT
Future<Map<String, dynamic>?> _gravarPedidoNoSupabase(Map<String, dynamic> payload) async {
  final ped = <String, dynamic>{...payload};

  // 🔴 GARANTE O CLIENTE NO SUPABASE E USA O ID REMOTO (evita 23503)
  ped['cliente_id'] = await ensureClienteSupabaseId(ped);

  Map<String, dynamic>? remoto; // linha resultante (insert/update/upsert)

  // -------- Tentativa A: UPSERT por (numero,vendedor_codigo)
  final temNumero = (ped['numero'] != null && '${ped['numero']}'.isNotEmpty);
  final temVend = (ped['vendedor_codigo'] != null && '${ped['vendedor_codigo']}'.isNotEmpty);

  if (temNumero && temVend) {
    try {
      remoto = await supabase
          .from('pedidos')
          .upsert(_stripNulls(ped), onConflict: 'numero,vendedor_codigo')
          .select()
          .maybeSingle();
    } catch (e) {
      final msg = e.toString();
      final noConstraint = msg.contains('no unique or exclusion constraint') ||
          (msg.contains('does not exist') && (msg.contains('numero') || msg.contains('vendedor_codigo')));
      if (!noConstraint) {
        rethrow; // erro real de rede ou validação
      }
      // vai para Tentativa B
    }
  }

  // -------- Tentativa B: procurar por (numero,vendedor_codigo) e UPDATE
  if (remoto == null && temNumero && temVend) {
    try {
      final existente = await supabase
          .from('pedidos')
          .select('id')
          .eq('numero', ped['numero'])
          .eq('vendedor_codigo', ped['vendedor_codigo'])
          .maybeSingle();

      if (existente != null && existente['id'] != null) {
        final idSrv = existente['id'];
        remoto = await supabase
            .from('pedidos')
            .update(_stripNulls(ped))
            .eq('id', idSrv)
            .select()
            .maybeSingle();
      }
    } catch (_) {
      // segue para Tentativa C
    }
  }

  // -------- Tentativa C: INSERT normal
  remoto ??= await supabase.from('pedidos').insert(_stripNulls(ped)).select().maybeSingle();
  return remoto;
}

/// Grava o payload no servidor e devolve o eco. Trocável nos testes.
@visibleForTesting
Future<Map<String, dynamic>?> Function(Map<String, dynamic> payload)
    gravarPedidoNoServidor = _gravarPedidoNoSupabase;

/// Salva/atualiza um pedido no Supabase (qualquer situação) e aplica o eco no
/// SQLite, limpando duplicados locais. ***Preserva sempre o `assinatura_path`
/// local***.
/// - Sem id_aparelho (pendente da v16): ganha um, gravado antes do envio.
/// - Pedido que ainda não chegou ao servidor: confere o número antes; se o
///   servidor tem esse (numero, vendedor) com outro id_aparelho, lança
///   [NumeroEmUso] sem enviar nada.
/// Devolve o [ResultadoEco], ou null se o servidor não devolveu a linha (aí
/// puxa os pedidos do vendedor). Roda sob [comTravaDePedidos].
Future<ResultadoEco?> salvarPedidoSupabase(Map<String, dynamic> pedido) =>
    comTravaDePedidos(() => _salvarPedidoSupabase(pedido));

Future<ResultadoEco?> _salvarPedidoSupabase(Map<String, dynamic> pedidoOriginal) async {
  try {
    final pedido = await _garantirIdAparelho(pedidoOriginal);
    final numero = pedido['numero']?.toString() ?? '';
    final vend = pedido['vendedor_codigo']?.toString() ?? '';

    if (!jaChegouAoServidor(pedido) && numero.isNotEmpty && vend.isNotEmpty) {
      final existente = await buscarRemotoPorNumero(numero, vend);
      if (existente != null &&
          conflitoDeNumero(_texto(pedido['id_aparelho']), _texto(existente['id_aparelho']))) {
        throw NumeroEmUso(numero, vend);
      }
    }

    final remoto = await gravarPedidoNoServidor(montarPayloadPedido(pedido));

    // Aplicar no SQLite e LIMPAR duplicados (se a cópia local não mudou
    // enquanto o envio estava no ar)
    if (remoto != null) {
      return await aplicarEcoDoServidor(enviado: pedido, remoto: remoto);
    }
    // Último recurso: puxa do servidor os pedidos do vendedor
    if (vend.isNotEmpty) await sincronizarPedidos(vendedorCodigo: vend);
    return null;
  } on NumeroEmUso {
    rethrow; // não é erro de envio: quem chamou marca erro_envio = 'numero'
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao salvar pedido no Supabase: $e');
    rethrow;
  }
}

// ---------------------- Eco do servidor no SQLite ----------------------

enum ResultadoEco {
  /// O eco foi gravado no SQLite (o servidor aceitou o que foi enviado).
  aplicado,

  /// A cópia local mudou com o envio no ar: o eco é descartado e a edição
  /// continua pendente.
  edicaoLocalMaisNova,

  /// O servidor tem o pedido finalizado/cancelado e diferente do enviado (o
  /// gatilho de proteção agiu). A versão local vai para `pedidos_descartados`
  /// e o eco é gravado.
  servidorFechou,
}

double _comoDouble(dynamic v) =>
    (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0.0;

/// O que identifica uma versão local do pedido: toda gravação das telas troca
/// `datahora`; `status` e `total` cobrem as demais.
bool _mesmaVersao(Map<String, dynamic> local, Map<String, dynamic> enviado) =>
    '${local['datahora'] ?? ''}' == '${enviado['datahora'] ?? ''}' &&
    '${local['status'] ?? ''}' == '${enviado['status'] ?? ''}' &&
    _comoDouble(local['total']) == _comoDouble(enviado['total']);

/// Itens normalizados (nome + quantidade), em ordem; null se não der para ler.
List<String>? _itensNormalizados(dynamic produtos) {
  dynamic lista = produtos;
  if (lista is String) {
    try {
      lista = jsonDecode(lista);
    } catch (_) {
      return null;
    }
  }
  if (lista == null) return const [];
  if (lista is! List) return null;
  final out = <String>[];
  for (final it in lista) {
    if (it is! Map) return null;
    out.add('${(it['nome'] ?? '').toString().trim()}|${_comoDouble(it['quantidade'])}');
  }
  out.sort();
  return out;
}

/// O servidor guardou o que foi enviado? Situação, total e itens.
bool _mesmoConteudo(Map<String, dynamic> enviado, Map<String, dynamic> remoto) {
  if ('${enviado['status'] ?? ''}' != '${remoto['status'] ?? ''}') return false;
  if ((_comoDouble(enviado['total']) - _comoDouble(remoto['total'])).abs() > 0.005) {
    return false;
  }
  final a = _itensNormalizados(enviado['produtos']);
  final b = _itensNormalizados(remoto['produtos']);
  if (a == null || b == null) return true; // sem como comparar: fica o resto
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decide o que fazer com o eco [remoto] do envio de [enviado], dada a cópia
/// [local] que está no SQLite agora.
ResultadoEco decidirEco(
  Map<String, dynamic> local,
  Map<String, dynamic> enviado,
  Map<String, dynamic> remoto,
) {
  if (!_mesmaVersao(local, enviado)) return ResultadoEco.edicaoLocalMaisNova;
  final st = '${remoto['status'] ?? ''}';
  if ((st == 'finalizado' || st == 'cancelado') && !_mesmoConteudo(enviado, remoto)) {
    return ResultadoEco.servidorFechou;
  }
  return ResultadoEco.aplicado;
}

/// Grava no SQLite a linha devolvida pelo servidor depois de enviar [enviado].
/// Numa transação, relê a cópia local (mesmo id ou mesmo numero+vendedor) e
/// decide com [decidirEco]:
/// - [ResultadoEco.edicaoLocalMaisNova]: o eco é descartado e a edição fica
///   como está, com seu `pendente_envio`;
/// - [ResultadoEco.servidorFechou]: a cópia local vai para
///   `pedidos_descartados` ('fechado no Controle') ANTES de o eco ser gravado;
/// - [ResultadoEco.aplicado]: o eco é gravado.
/// O eco gravado leva id_aparelho (o do servidor, senão o local), as cópias
/// de auditoria, `so_local = 0` e `erro_envio = null`. Preserva sempre o
/// `assinatura_path` local.
Future<ResultadoEco> aplicarEcoDoServidor({
  required Map<String, dynamic> enviado,
  required Map<String, dynamic> remoto,
}) async {
  final int? idLocalAntigo = _idDe(enviado);
  final String? assinaturaPathLocal = enviado['assinatura_path']?.toString();
  final numero = enviado['numero']?.toString();
  final vend = enviado['vendedor_codigo']?.toString();

  final produtosLocal = (remoto['produtos'] is String)
      ? remoto['produtos']
      : jsonEncode(remoto['produtos'] ?? []);

  final mapLocal = <String, dynamic>{
    'id': remoto['id'],
    'numero': remoto['numero']?.toString(),
    'produtos': produtosLocal,
    'total': _comoDouble(remoto['total']),
    'status': (remoto['status'] ?? 'salvo').toString(),
    'datahora': remoto['datahora'],
    'vendedor_codigo': remoto['vendedor_codigo']?.toString(),
    'vendedor_nome': remoto['vendedor_nome']?.toString(),
    'cliente_id': (remoto['cliente_id'] is int) ? remoto['cliente_id'] : null,
    'cliente_nome': remoto['cliente_nome']?.toString(),
    'assinatura': _toHex0x(remoto['assinatura']),
    'cliente_telefone': remoto['cliente_telefone']?.toString(),
    'cliente_endereco': remoto['cliente_endereco']?.toString(),
    'cliente_cidade': remoto['cliente_cidade']?.toString(),
    'cliente_cpf_cnpj': remoto['cliente_cpf_cnpj']?.toString(),
    'cliente_insc_estadual': remoto['cliente_insc_estadual']?.toString(),
    'cliente_cep': remoto['cliente_cep']?.toString(),
    'cliente_anotacao': remoto['cliente_anotacao']?.toString(),
    // ficarão null caso o servidor não tenha essas colunas
    'cliente_nome_fantasia': remoto['cliente_nome_fantasia']?.toString(),
    'cliente_whatsapp': remoto['cliente_whatsapp']?.toString(),
    'cliente_email': remoto['cliente_email']?.toString(),

    // 👇 PRESERVAR SEMPRE o caminho local da assinatura ao regravar no SQLite
    'assinatura_path': assinaturaPathLocal,

    // O servidor confirmou: não está mais aguardando envio.
    'pendente_envio': 0,
  };

  final db = await getDb();
  return db.transaction((txn) async {
    final locais = [
      for (final l in await txn.query(
        'pedidos',
        where: 'id = ? OR (numero = ? AND vendedor_codigo = ?)',
        whereArgs: [idLocalAntigo ?? -1, numero, vend],
      ))
        Map<String, dynamic>.from(l),
    ];

    var resultado = ResultadoEco.aplicado;
    for (final l in locais.isEmpty ? [enviado] : locais) {
      final d = decidirEco(l, enviado, remoto);
      if (d == ResultadoEco.edicaoLocalMaisNova) {
        // ignore: avoid_print
        print('⏭️ Pedido ${numero ?? idLocalAntigo} mudou durante o envio; eco do servidor ignorado.');
        return d;
      }
      if (d == ResultadoEco.servidorFechou) resultado = d;
    }

    if (resultado == ResultadoEco.servidorFechou) {
      // A versão local perdeu para a do servidor: nunca some sem cópia.
      for (final l in locais.isEmpty ? [enviado] : locais) {
        await guardarVersaoDescartada(l, 'fechado no Controle', em: txn);
      }
      // ignore: avoid_print
      print('🔒 Pedido ${numero ?? idLocalAntigo} já fechado no Controle; versão local guardada.');
    }

    String? idAparelhoLocal = _texto(enviado['id_aparelho']);
    for (final l in locais) {
      idAparelhoLocal ??= _texto(l['id_aparelho']);
    }
    mapLocal.addAll(_camposDoServidor(remoto, idAparelhoLocal));

    await txn.insert('pedidos', mapLocal, conflictAlgorithm: ConflictAlgorithm.replace);
    // Limpa duplicados locais (apaga o antigo e qualquer outro com mesma chave)
    await _limparDuplicadosLocais(txn: txn, remoto: remoto, idLocalAntigo: idLocalAntigo);
    return resultado;
  });
}

// ---------------------- Gravar e enviar (telas de pedido) ----------------------

enum ResultadoGravacao {
  /// Rascunho antigo só do aparelho (`so_local = 1`): gravado, não enviado.
  rascunho,

  /// Gravado e enviado (qualquer situação: aberto, finalizado ou cancelado).
  enviado,

  /// Gravado no aparelho; o envio falhou (rede) e fica pendente.
  pendente,

  /// Enviado, mas o pedido já estava fechado (finalizado/cancelado) no
  /// Controle: vale a versão do servidor; a local foi guardada em
  /// `pedidos_descartados`.
  fechadoNoControle,

  /// O número já é de outro pedido no servidor: fica pendente com
  /// `erro_envio = 'numero'` até o vendedor trocar o número.
  numeroEmUso,
}

/// Linha do SQLite do pedido recém-gravado (por id, senão por numero+vendedor).
Future<Map<String, dynamic>?> _linhaGravada(Map<String, dynamic> pedido) async {
  final db = await getDb();
  final id = _idDe(pedido);
  final r = id != null
      ? await db.query('pedidos', where: 'id = ?', whereArgs: [id], limit: 1)
      : await db.query('pedidos',
          where: 'numero = ? AND vendedor_codigo = ?',
          whereArgs: [pedido['numero']?.toString(), pedido['vendedor_codigo']?.toString()],
          limit: 1);
  return r.isEmpty ? null : Map<String, dynamic>.from(r.first);
}

/// Grava o pedido no SQLite **na hora** (fora da trava: nada espera a rede) e,
/// se não for rascunho antigo (`so_local`), tenta enviar. Falha de envio não é
/// erro: o pedido já está salvo com `pendente_envio = 1`. Só lança se a
/// gravação local falhar.
///
/// O valor que [enviar] devolve é lido: [salvarPedidoSupabase] devolve o
/// [ResultadoEco]; qualquer outro valor (ou nenhum) conta como enviado.
Future<ResultadoGravacao> gravarPedidoEEnviar(
  Map<String, dynamic> pedido, {
  required bool novo,
  Future<void> Function(Map<String, dynamic>) enviar = salvarPedidoSupabase,
}) async {
  if (novo) {
    await salvarPedidoLocal(pedido);
  } else {
    await atualizarPedidoLocal(pedido);
  }
  final gravado = await _linhaGravada(pedido);
  final soLocal = gravado?['so_local'] ?? pedido['so_local'];
  if (soLocal == 1 || soLocal == true || '$soLocal' == '1') {
    return ResultadoGravacao.rascunho;
  }

  // Envia com o id e o id_aparelho que ficaram no aparelho (o mapa da tela
  // de pedido novo não tem nenhum dos dois).
  final envio = <String, dynamic>{
    ...pedido,
    if (gravado?['id'] != null) 'id': gravado!['id'],
    if (_texto(gravado?['id_aparelho']) != null) 'id_aparelho': gravado!['id_aparelho'],
  };
  try {
    // Future<void> é Future<Object?>: lê o ResultadoEco de salvarPedidoSupabase.
    final Future<Object?> envioNoAr = enviar(envio);
    final r = await envioNoAr;
    if (r == ResultadoEco.servidorFechou) return ResultadoGravacao.fechadoNoControle;
    return ResultadoGravacao.enviado;
  } on NumeroEmUso catch (e) {
    // ignore: avoid_print
    print('⚠️ $e');
    await _marcarNumeroEmUso(envio);
    return ResultadoGravacao.numeroEmUso;
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Pedido ${pedido['numero']} salvo no aparelho; envio pendente: $e');
    return ResultadoGravacao.pendente;
  }
}
