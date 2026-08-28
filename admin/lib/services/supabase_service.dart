// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';
import '../models/pedido.dart';
import '../models/produto.dart';
import '../models/vendedor.dart';

typedef JsonMap = Map<String, dynamic>;

class RepoFailure implements Exception {
  final String message;
  RepoFailure(this.message);
  @override
  String toString() => 'RepoFailure: $message';
}

/// Paginação simples (offset-based)
class PageResult<T> {
  final List<T> items;
  final int from;
  final int to;
  final bool hasMore;
  const PageResult({
    required this.items,
    required this.from,
    required this.to,
    required this.hasMore,
  });
}

class SupabaseService {
  final SupabaseClient _sb;
  SupabaseService([SupabaseClient? injected]) : _sb = injected ?? Supabase.instance.client;

  // ----------------- helpers -----------------
  String _escapeIlike(String input) => input.replaceAll('%', '').replaceAll('_', '');

  bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v?.toString().toLowerCase() == 'true';
  }

  DateTime? _parseIso(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  JsonMap _coerceToMap(dynamic obj) {
    if (obj is Map) return Map<String, dynamic>.from(obj);
    try { final r = (obj as dynamic).toInsertMap(); if (r is Map) return Map<String, dynamic>.from(r); } catch (_) {}
    try { final r = (obj as dynamic).toUpdateMap(); if (r is Map) return Map<String, dynamic>.from(r); } catch (_) {}
    try { final r = (obj as dynamic).toMap();        if (r is Map) return Map<String, dynamic>.from(r); } catch (_) {}
    try { final r = (obj as dynamic).toJson();       if (r is Map) return Map<String, dynamic>.from(r); } catch (_) {}
    throw RepoFailure('Objeto fornecido não é Map e não expõe toInsertMap/toUpdateMap/toMap/toJson.');
  }

  // --------- mapeamentos DB <-> modelo (normaliza chaves) ---------
  JsonMap _produtoDbToModel(JsonMap m) => {
    'id'       : m['id'],
    'codigo'   : m['codigo'] ?? m['código'],
    'nome'     : m['nome'],
    'unidade'  : m['unidade'],
    'preco'    : m['preco'] ?? m['preço'],
    'descricao': m['descricao'] ?? m['descrição'],
    'ativo'    : _toBool(m['ativo']),
    'datahora' : m['datahora'],
  };

  JsonMap _produtoModelToDb(JsonMap m) => {
    'id'       : m['id'],
    'código'   : _nullIfEmpty(m['codigo']),
    'nome'     : _nullIfEmpty(m['nome']),
    'unidade'  : _nullIfEmpty(m['unidade']),
    'preço'    : m['preco'],
    'descrição': _nullIfEmpty(m['descricao']),
    'ativo'    : m['ativo'],
    'datahora' : m['datahora'],
  };

  JsonMap _vendedorDbToModel(JsonMap m) => {
    'id'      : m['id'],
    'codigo'  : m['codigo'] ?? m['código'],
    'nome'    : m['nome'],
    'senha'   : m['senha'],
    'anotacao': m['anotacao'] ?? m['anotação'],
    'ativo'   : _toBool(m['ativo']),
  };

  JsonMap _vendedorModelToDb(JsonMap m) => {
    'id'      : m['id'],
    'código'  : _nullIfEmpty(m['codigo']),
    'nome'    : _nullIfEmpty(m['nome']),
    'senha'   : _nullIfEmpty(m['senha']),
    'anotação': _nullIfEmpty(m['anotacao']),
    'ativo'   : m['ativo'],
  };

  JsonMap _clienteDbToModel(JsonMap m) => {
    'id'            : m['id'],
    'nome'          : m['nome'],
    'nome_fantasia' : m['nome_fantasia'],
    'endereco'      : m['endereco'],
    'cidade'        : m['cidade'],
    'cep'           : m['cep'] ?? m['cepa'],
    'cpf_cnpj'      : m['cpf_cnpj'],
    'insc_estadual' : m['insc_estadual'],
    'telefone'      : m['telefone'],
    'whatsapp'      : m['whatsapp'] ?? m['WhatsApp'],
    'email'         : m['email'] ?? m['e-mail'],
    'anotacao'      : m['anotacao'] ?? m['anotação'],
    'ativo'         : _toBool(m['ativo']),
    'datahora'      : m['datahora'],
    'ultimo_pedido' : m['ultimo_pedido'] ?? m['último_pedido'],
  };

  JsonMap _clienteModelToDb(JsonMap m) => {
    'id'            : m['id'],
    'nome'          : _nullIfEmpty(m['nome']),
    'nome_fantasia' : _nullIfEmpty(m['nome_fantasia']),
    'endereco'      : _nullIfEmpty(m['endereco']),
    'cidade'        : _nullIfEmpty(m['cidade']),
    'cep'           : _nullIfEmpty(m['cep']),
    'cpf_cnpj'      : _nullIfEmpty(m['cpf_cnpj']),
    'insc_estadual' : _nullIfEmpty(m['insc_estadual']),
    'telefone'      : _nullIfEmpty(m['telefone']),
    'WhatsApp'      : _nullIfEmpty(m['whatsapp']),
    'e-mail'        : _nullIfEmpty(m['email']),
    'anotacao'      : _nullIfEmpty(m['anotacao']),
    'ativo'         : m['ativo'],
    'datahora'      : m['datahora'],
  };

  JsonMap _pedidoDbToModel(JsonMap m) => {
    'id'                    : m['id'],
    'datahora'              : m['datahora'],
    'status'                : m['status'],
    'total'                 : m['total'],
    'numero'                : m['numero'] ?? m['número'],
    'vendedor_codigo'       : m['vendedor_codigo'],
    'vendedor_nome'         : m['vendedor_nome'],
    'cliente_id'            : m['cliente_id'] ?? m['ID do cliente'],
    'cliente_nome'          : m['cliente_nome'] ?? m['nome_do_cliente'] ?? m['cliente_nome_fantasia'],
    'cliente_email'         : m['cliente_email'] ?? m['e-mail do cliente'],
    'cliente_whatsapp'      : m['cliente_whatsapp'] ?? m['cliente_whatspp'],
    'cliente_telefone'      : m['cliente_telefone'],
    'cliente_endereco'      : m['cliente_endereco'],
    'cliente_cidade'        : m['cliente_cidade'],
    'cliente_cpf_cnpj'      : m['cliente_cpf_cnpj'],
    'cliente_insc_estadual' : m['cliente_insc_estadual'],
    'cliente_cep'           : m['cliente_cep'],
    'cliente_anotacao'      : m['cliente_anotacao'],
    'produtos'              : m['produtos'],
  };

  JsonMap _pedidoModelToDb(JsonMap m) => {
    'id'                    : m['id'],
    'datahora'              : m['datahora'],
    'status'                : m['status'],
    'total'                 : m['total'],
    'número'                : _nullIfEmpty(m['numero']),
    'vendedor_codigo'       : _nullIfEmpty(m['vendedor_codigo']),
    'vendedor_nome'         : _nullIfEmpty(m['vendedor_nome']),
    'ID do cliente'         : m['cliente_id'],
    'nome_do_cliente'       : _nullIfEmpty(m['cliente_nome']),
    'e-mail do cliente'     : _nullIfEmpty(m['cliente_email']),
    'cliente_whatspp'       : _nullIfEmpty(m['cliente_whatsapp']),
    'cliente_telefone'      : _nullIfEmpty(m['cliente_telefone']),
    'cliente_endereco'      : _nullIfEmpty(m['cliente_endereco']),
    'cliente_cidade'        : _nullIfEmpty(m['cliente_cidade']),
    'cliente_cpf_cnpj'      : _nullIfEmpty(m['cliente_cpf_cnpj']),
    'cliente_insc_estadual' : _nullIfEmpty(m['cliente_insc_estadual']),
    'cliente_cep'           : _nullIfEmpty(m['cliente_cep']),
    'cliente_anotacao'      : _nullIfEmpty(m['cliente_anotacao']),
    'produtos'              : m['produtos'],
  };

  String? _nullIfEmpty(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  // ----------------- CLIENTES -----------------
  Future<List<Cliente>> buscarClientes({
    String? q,
    bool? somenteAtivos,
    bool withUltimoPedido = true,
    int? limit,
    int? offset,
  }) async {
    try {
      final table = withUltimoPedido ? 'clientes_com_ultimo_pedido' : 'clientes';
      final query = _sb.from(table).select();

      if (q != null && q.trim().isNotEmpty) {
        final term = _escapeIlike(q.trim());
        // inclui colunas com acento/maiúsculas usando aspas
        query.or(
          'nome.ilike.%$term%,'
              'nome_fantasia.ilike.%$term%,'
              'cpf_cnpj.ilike.%$term%,'
              'telefone.ilike.%$term%,'
              'cidade.ilike.%$term%,'
              '"WhatsApp".ilike.%$term%,'
              '"e-mail".ilike.%$term%',
        );
      }
      if (somenteAtivos != null) query.eq('ativo', somenteAtivos);

      var run = query.order('nome', ascending: true);
      if (limit != null) {
        final from = offset ?? 0;
        final to = from + limit - 1;
        run = run.range(from, to);
      }

      final List<dynamic> raw = await run;
      final rows = raw.map((e) => JsonMap.from(e as Map)).toList();

      // normaliza chaves e chama o fromMap do modelo
      return rows.map((m) => Cliente.fromMap(_clienteDbToModel(m))).toList();
    } catch (e) {
      throw RepoFailure('Erro ao buscar clientes: $e');
    }
  }

  Future<PageResult<Cliente>> paginarClientes({
    String? q,
    bool? somenteAtivos,
    int limit = 30,
    int offset = 0,
  }) async {
    final items = await buscarClientes(
      q: q,
      somenteAtivos: somenteAtivos,
      withUltimoPedido: true,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = items.length > limit;
    return PageResult(
      items: hasMore ? items.take(limit).toList() : items,
      from: offset,
      to: offset + (hasMore ? limit : items.length),
      hasMore: hasMore,
    );
  }

  // ----------------- PRODUTOS -----------------
  Future<List<Produto>> buscarProdutos({
    String? q,
    bool? somenteAtivos,
    int? limit,
    int? offset,
  }) async {
    try {
      final query = _sb.from('produtos').select();

      if (q != null && q.trim().isNotEmpty) {
        final term = _escapeIlike(q.trim());
        query.or('nome.ilike.%$term%,"descrição".ilike.%$term%');
      }
      if (somenteAtivos != null) query.eq('ativo', somenteAtivos);

      var run = query.order('nome', ascending: true);
      if (limit != null) {
        final from = offset ?? 0;
        final to = from + limit - 1;
        run = run.range(from, to);
      }

      final List<dynamic> raw = await run;
      final rows = raw.map((e) => JsonMap.from(e as Map)).toList();
      return rows.map((m) => Produto.fromMap(_produtoDbToModel(m))).toList();
    } catch (e) {
      throw RepoFailure('Erro ao buscar produtos: $e');
    }
  }

  Future<PageResult<Produto>> paginarProdutos({
    String? q,
    bool? somenteAtivos,
    int limit = 30,
    int offset = 0,
  }) async {
    final items = await buscarProdutos(
      q: q,
      somenteAtivos: somenteAtivos,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = items.length > limit;
    return PageResult(
      items: hasMore ? items.take(limit).toList() : items,
      from: offset,
      to: offset + (hasMore ? limit : items.length),
      hasMore: hasMore,
    );
  }

  // ----------------- VENDEDORES -----------------
  Future<List<Vendedor>> buscarVendedores({
    String? q,
    bool? somenteAtivos,
    int? limit,
    int? offset,
  }) async {
    try {
      final query = _sb.from('vendedores').select();

      if (q != null && q.trim().isNotEmpty) {
        final term = _escapeIlike(q.trim());
        query.or('nome.ilike.%$term%,"código".ilike.%$term%');
      }
      if (somenteAtivos != null) query.eq('ativo', somenteAtivos);

      var run = query.order('nome', ascending: true);
      if (limit != null) {
        final from = offset ?? 0;
        final to = from + limit - 1;
        run = run.range(from, to);
      }

      final List<dynamic> raw = await run;
      final rows = raw.map((e) => JsonMap.from(e as Map)).toList();
      return rows.map((m) => Vendedor.fromMap(_vendedorDbToModel(m))).toList();
    } catch (e) {
      throw RepoFailure('Erro ao buscar vendedores: $e');
    }
  }

  // ====== LOGIN ======
  Future<Vendedor?> autenticarVendedor(String codigo, String senha) async {
    try {
      final res = await _sb
          .from('vendedores')
          .select('id,"código",nome,ativo,anotação') // sem "senha"
          .eq('código', codigo) // <- coluna com acento
          .maybeSingle();

      final row = (res == null) ? null : Map<String, dynamic>.from(res as Map);
      if (row == null) return null;
      if (!_toBool(row['ativo'])) return null;

      final ok = await autenticarAdmin(senha);
      if (!ok) return null;

      // normaliza para o modelo
      return Vendedor.fromMap(_vendedorDbToModel(row));
    } catch (e) {
      throw RepoFailure('Erro ao autenticar (vendedor via acesso_admin): $e');
    }
  }

  Future<bool> autenticarAdmin(String senha) async {
    try {
      final pass = senha.trim();
      if (pass.isEmpty) return false;

      final res = await _sb
          .from('acesso_admin')
          .select('id')
          .eq('ativo', true)
          .eq('senha', pass)
          .limit(1)
          .maybeSingle();

      return res != null;
    } catch (e) {
      throw RepoFailure('Erro ao verificar acesso admin: $e');
    }
  }

  // ----------------- PEDIDOS -----------------
  Future<List<Pedido>> buscarPedidos({
    String? q,
    String? status, // 'emitido' | 'enviado' | 'finalizado' | 'cancelado'
    DateTime? de,
    DateTime? ate,
    String? vendedorCodigo,
    int? limit,
    int? offset,
  }) async {
    try {
      final query = _sb.from('pedidos').select();

      if (q != null && q.trim().isNotEmpty) {
        final term = _escapeIlike(q.trim());
        query.or(
          'vendedor_nome.ilike.%$term%,'
              'nome_do_cliente.ilike.%$term%,'
              '"cliente_nome_fantasia".ilike.%$term%,'
              '"número".ilike.%$term%',
        );
      }
      if (status != null && status.isNotEmpty) query.eq('status', status);
      if (vendedorCodigo != null && vendedorCodigo.isNotEmpty) {
        query.eq('vendedor_codigo', vendedorCodigo);
      }
      if (de != null) query.gte('datahora', de.toIso8601String());
      if (ate != null) query.lte('datahora', ate.toIso8601String());

      var run = query.order('datahora', ascending: false);
      if (limit != null) {
        final from = offset ?? 0;
        final to = from + limit - 1;
        run = run.range(from, to);
      }

      final List<dynamic> raw = await run;
      final rows = raw.map((e) => JsonMap.from(e as Map)).toList();
      return rows.map((m) => Pedido.fromMap(_pedidoDbToModel(m))).toList();
    } catch (e) {
      throw RepoFailure('Erro ao buscar pedidos: $e');
    }
  }

  Future<PageResult<Pedido>> paginarPedidos({
    String? q,
    String? status,
    DateTime? de,
    DateTime? ate,
    String? vendedorCodigo,
    int limit = 30,
    int offset = 0,
  }) async {
    final items = await buscarPedidos(
      q: q,
      status: status,
      de: de,
      ate: ate,
      vendedorCodigo: vendedorCodigo,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = items.length > limit;
    return PageResult(
      items: hasMore ? items.take(limit).toList() : items,
      from: offset,
      to: offset + (hasMore ? limit : items.length),
      hasMore: hasMore,
    );
  }

  /// Stream realtime (ordenado por datahora desc)
  Stream<List<Pedido>> streamPedidos() {
    return _sb
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .order('datahora', ascending: false)
        .map((rows) => rows.map((e) => Pedido.fromMap(_pedidoDbToModel(JsonMap.from(e as Map)))).toList());
  }

  Future<Pedido> inserirPedido(dynamic pedido) async {
    try {
      final model = _coerceToMap(pedido);
      model['datahora'] ??= DateTime.now().toIso8601String();
      final payload = _pedidoModelToDb(model);
      final JsonMap inserted = await _sb.from('pedidos').insert(payload).select().single();
      return Pedido.fromMap(_pedidoDbToModel(JsonMap.from(inserted)));
    } catch (e) {
      throw RepoFailure('Erro ao inserir pedido: $e');
    }
  }

  Future<Pedido> atualizarPedido(dynamic pedido) async {
    try {
      final model = _coerceToMap(pedido);
      final id = model['id'] ?? (pedido as dynamic).id;
      if (id == null) throw RepoFailure('Pedido sem ID para atualizar');

      final payload = _pedidoModelToDb(model);
      final JsonMap updated =
      await _sb.from('pedidos').update(payload).eq('id', id as Object).select().single();
      return Pedido.fromMap(_pedidoDbToModel(JsonMap.from(updated)));
    } catch (e) {
      throw RepoFailure('Erro ao atualizar pedido: $e');
    }
  }

  Future<void> deletarPedido(int id) async {
    try {
      await _sb.from('pedidos').delete().eq('id', id);
    } catch (e) {
      throw RepoFailure('Erro ao deletar pedido: $e');
    }
  }
}
