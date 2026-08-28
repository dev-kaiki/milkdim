// lib/utils/produto_service.dart
//
// Busca e sincronização de produtos (offline-first).
// Lê direto do SQLite e, quando possível, atualiza a base local a partir do Supabase.
// Obs: campos extras (codigo, unidade, ativo) são persistidos localmente para manter o filtro.

import 'produto.dart';
import 'db.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// -------------------- LOCAL --------------------

Future<List<Produto>> buscarProdutosLocal({bool apenasAtivos = true}) async {
  final db = await getDb();
  final rows = await db.query(
    'produtos',
    where: apenasAtivos ? 'ativo IS NULL OR ativo = 1' : null,
    orderBy: 'nome COLLATE NOCASE ASC',
  );

  return rows.map((e) {
    final m = Map<String, dynamic>.from(e);
    final preco = m['preco'];
    if (preco is int) m['preco'] = preco.toDouble();
    return Produto.fromMap(m);
  }).toList();
}

/// -------------------- SUPABASE --------------------

Future<List<Produto>> buscarProdutosSupabase({bool apenasAtivos = true}) async {
  // Pede todos os campos úteis (se existirem na tabela do Supabase)
  var query = _sb.from('produtos').select('id,codigo,unidade,nome,preco,ativo');
  if (apenasAtivos) query = query.eq('ativo', true);

  final data = await query; // List<dynamic>
  final out = <Produto>[];

  for (final row in data) {
    final m = Map<String, dynamic>.from(row as Map);

    // normalização de preço
    final preco = m['preco'];
    if (preco is String) {
      final parsed = double.tryParse(preco.replaceAll(',', '.'));
      if (parsed != null) m['preco'] = parsed;
    } else if (preco is int) {
      m['preco'] = preco.toDouble();
    } else if (preco is num) {
      m['preco'] = (preco as num).toDouble();
    }

    out.add(Produto.fromMap(m));
  }
  return out;
}

Future<int> sincronizarProdutosLocalComSupabase({bool apenasAtivos = true}) async {
  final produtosSupabase = await buscarProdutosSupabase(apenasAtivos: apenasAtivos);
  final db = await getDb();

  await db.transaction((txn) async {
    // Zera e repovoa para manter paridade com o estado remoto filtrado
    await txn.delete('produtos');

    final batch = txn.batch();
    for (final produto in produtosSupabase) {
      batch.insert(
        'produtos',
        {
          if (produto.id != null) 'id': produto.id,
          // Estes campos extras são ignorados pelo Produto.fromMap se não existir no model,
          // mas ficam no SQLite para futuras telas/filtros.
          'codigo': (produto as dynamic).codigo,   // se não existir no model, não tem problema
          'unidade': (produto as dynamic).unidade, // idem
          'nome': produto.nome,
          'preco': produto.preco,
          'ativo': (produto as dynamic).ativo == null
              ? 1
              : ((produto as dynamic).ativo is bool
              ? ((produto as dynamic).ativo ? 1 : 0)
              : (produto as dynamic).ativo),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  });

  return produtosSupabase.length;
}

/// Tenta baixar do Supabase e sincroniza o SQLite.
/// Se offline/erro, cai para o cache local.
Future<List<Produto>> buscarProdutosOnlineOuLocal({bool apenasAtivos = true}) async {
  try {
    final remotos = await buscarProdutosSupabase(apenasAtivos: apenasAtivos);
    if (remotos.isNotEmpty) {
      await sincronizarProdutosLocalComSupabase(apenasAtivos: apenasAtivos);
      // Depois de sincronizar, sempre retorna a fonte local (garante consistência na UI)
      return buscarProdutosLocal(apenasAtivos: apenasAtivos);
    }
  } catch (_) {
    // offline ou erro — ignora e usa cache
  }
  return buscarProdutosLocal(apenasAtivos: apenasAtivos);
}
