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

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'convert.dart'; // assinaturaToBytes(), bytesToHex0x()
import 'db.dart';      // getDb()

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

// ---------------------- Sincronização geral ----------------------

Future<bool> sincronizarTudo() async {
  try {
    await sincronizarClientes();
    await sincronizarVendedores();
    await sincronizarProdutos();
    await sincronizarPedidos();
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar tudo: $e');
    return false;
  }
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

// ---------------------- VENDEDORES ----------------------

Future<void> sincronizarVendedores() async {
  try {
    final response = await supabase.from('vendedores').select('*');
    final List<dynamic> vendedores = response;

    final db = await getDb();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final raw in vendedores) {
        final v = Map<String, dynamic>.from(raw as Map);
        final map = <String, dynamic>{
          'codigo': v['codigo'],
          'nome': v['nome'],
          'senha': v['senha'],
          'ativo': (v['ativo'] is bool)
              ? (v['ativo'] == true ? 1 : 0)
              : (v['ativo'] is int ? v['ativo'] : 1),
        };
        batch.insert('vendedores', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    // ignore: avoid_print
    print('🟢 Vendedores sincronizados (${vendedores.length})');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar vendedores: $e');
  }
}

Future<void> inserirVendedorSupabase(Map<String, dynamic> vendedor) async {
  try {
    await supabase.from('vendedores').insert(_stripNulls(vendedor));
    // ignore: avoid_print
    print('✅ Vendedor enviado ao Supabase');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao enviar vendedor: $e');
  }
}

Future<Map<String, dynamic>?> loginSupabaseVendedor(String codigo, String senha) async {
  try {
    final response = await supabase
        .from('vendedores')
        .select()
        .eq('codigo', codigo)
        .eq('senha', senha)
        .maybeSingle();
    return response;
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro no login vendedor: $e');
    return null;
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
  }
}

Future<void> inserirProdutoSupabase(Map<String, dynamic> produto) async {
  try {
    await supabase.from('produtos').insert(_stripNulls(produto));
    // ignore: avoid_print
    print('✅ Produto enviado ao Supabase');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao enviar produto: $e');
  }
}

// ---------------------- PEDIDOS ----------------------

Future<void> sincronizarPedidos() async {
  try {
    final response = await supabase.from('pedidos').select('*');
    final List<dynamic> pedidos = response;

    final db = await getDb();
    await db.transaction((txn) async {
      // 🛡️ Protege rascunhos locais: se algum pedido remoto traz um id que
      // colide com um rascunho local (status='salvo'), realoca o rascunho para
      // a faixa de id local segura ANTES de aplicar os remotos. Sem isso, o
      // `INSERT OR REPLACE` abaixo apagaria o rascunho.
      for (final raw in pedidos) {
        final m = Map<String, dynamic>.from(raw as Map);
        final rid =
            (m['id'] is int) ? m['id'] as int : int.tryParse('${m['id'] ?? ''}');
        if (rid == null) continue;
        final col = await txn.query(
          'pedidos',
          columns: ['id', 'status'],
          where: 'id = ?',
          whereArgs: [rid],
          limit: 1,
        );
        if (col.isNotEmpty && col.first['status']?.toString() == 'salvo') {
          final novoId = await proximoIdLocalSeguro(txn);
          await txn.update('pedidos', {'id': novoId},
              where: 'id = ?', whereArgs: [rid]);
        }
      }

      final batch = txn.batch();
      for (final raw in pedidos) {
        final ped = Map<String, dynamic>.from(raw as Map);

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
          // `assinatura_path` não existe no servidor; ficará null ao sincronizar tudo.
        };

        batch.insert('pedidos', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    // ignore: avoid_print
    print('🟢 Pedidos sincronizados (${pedidos.length})');
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao sincronizar pedidos: $e');
  }
}

/// Sobe pedidos "finalizados" que ficaram locais quando estava offline.
/// Chame ao abrir o app, ao entrar na tela de Pedidos e num botão "Sincronizar".
Future<void> subirPedidosPendentes({String? vendedorCodigo}) async {
  final db = await getDb();
  final where = vendedorCodigo == null ? 'status = ?' : 'status = ? AND vendedor_codigo = ?';
  final args = vendedorCodigo == null ? ['finalizado'] : ['finalizado', vendedorCodigo];

  final rows = await db.query(
    'pedidos',
    where: where,
    whereArgs: args,
    orderBy: 'datetime(datahora) ASC',
  );

  for (final ped in rows) {
    try {
      await salvarPedidoSupabase(ped);
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ Falha ao subir pendente ${ped['numero'] ?? ped['id']}: $e');
    }
  }
}

/// Apaga duplicados locais após salvar no servidor:
/// - Remove o registro local antigo (idLocalAntigo)
/// - Remove qualquer outro com o mesmo (numero, vendedor_codigo) e id != idNovo
Future<void> _limparDuplicadosLocais({
  required Database db,
  required Map<String, dynamic> remoto,
  int? idLocalAntigo,
}) async {
  final idNovo = (remoto['id'] is int)
      ? (remoto['id'] as int)
      : int.tryParse('${remoto['id']}') ?? -1;

  final numero = (remoto['numero'] ?? '').toString();
  final vend = (remoto['vendedor_codigo'] ?? '').toString();
  final temNumero = numero.isNotEmpty;

  await db.transaction((txn) async {
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
  });
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

// ---------------------- Salvar pedido (com FK garantida) ----------------------

/// Salva/atualiza um pedido no Supabase.
/// - Se o Supabase tiver `numero` + índice único com `vendedor_codigo`, usa UPSERT
/// - Se NÃO tiver, tenta localizar por (numero,vendedor_codigo) e faz UPDATE por id; se não achar, INSERT
/// Em todos os casos, aplica o retorno no SQLite e LIMPA duplicados locais.
/// ***E preserva sempre o `assinatura_path` local***.
Future<void> salvarPedidoSupabase(Map<String, dynamic> pedido) async {
  try {
    final int? idLocalAntigo =
    (pedido['id'] is int) ? (pedido['id'] as int) : int.tryParse('${pedido['id']}');

    // 👇 Guardar para regravar no SQLite após a resposta do servidor
    final String? assinaturaPathLocal = (pedido['assinatura_path'] as String?);

    // 🔴 GARANTE O CLIENTE NO SUPABASE E USA O ID REMOTO
    final int clienteIdRemoto = await ensureClienteSupabaseId(pedido);

    // Clona e limpa campos não enviados ao Supabase (pois não existem no seu schema)
    final ped = <String, dynamic>{...pedido};
    ped.remove('id'); // id é do servidor
    ped.remove('cliente_nome_fantasia');
    ped.remove('cliente_whatsapp');
    ped.remove('cliente_email');
    ped.remove('assinatura_path'); // 👈 NÃO enviar essa coluna ao servidor

    // Força usar o id remoto válido (evita 23503)
    ped['cliente_id'] = clienteIdRemoto;

    // produtos: aceita String (JSON) ou List
    if (ped['produtos'] is! String && ped['produtos'] is! List) {
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

    // Aplicar no SQLite e LIMPAR duplicados
    if (remoto != null) {
      final db = await getDb();

      final produtosLocal = (remoto['produtos'] is String)
          ? remoto['produtos']
          : jsonEncode(remoto['produtos'] ?? []);

      final assinaturaHex = _toHex0x(remoto['assinatura']);

      final mapLocal = <String, dynamic>{
        'id': remoto['id'],
        'numero': remoto['numero']?.toString(),
        'produtos': produtosLocal,
        'total': (remoto['total'] is num)
            ? (remoto['total'] as num).toDouble()
            : double.tryParse('${remoto['total']}') ?? 0.0,
        'status': (remoto['status'] ?? 'salvo').toString(),
        'datahora': remoto['datahora'],
        'vendedor_codigo': remoto['vendedor_codigo']?.toString(),
        'vendedor_nome': remoto['vendedor_nome']?.toString(),
        'cliente_id': (remoto['cliente_id'] is int) ? remoto['cliente_id'] : null,
        'cliente_nome': remoto['cliente_nome']?.toString(),
        'assinatura': assinaturaHex,
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
      };

      await db.insert('pedidos', mapLocal, conflictAlgorithm: ConflictAlgorithm.replace);

      // Limpa duplicados locais (apaga o antigo e qualquer outro com mesma chave)
      await _limparDuplicadosLocais(db: db, remoto: remoto, idLocalAntigo: idLocalAntigo);

      // ignore: avoid_print
      print('✅ Pedido salvo/atualizado no Supabase e conciliado no SQLite (preservando assinatura_path).');
    } else {
      // Último recurso: puxa tudo do servidor
      await sincronizarPedidos();
    }
  } catch (e) {
    // ignore: avoid_print
    print('❌ Erro ao salvar pedido no Supabase: $e');
    rethrow;
  }
}
