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

/// Filtros do PostgREST `or(...)`: so colunas reais do schema (sem acento).
String filtroBuscaClientes(String t) =>
    'nome.ilike.%$t%,nome_fantasia.ilike.%$t%,cpf_cnpj.ilike.%$t%,'
    'telefone.ilike.%$t%,cidade.ilike.%$t%,whatsapp.ilike.%$t%,email.ilike.%$t%';

String filtroBuscaProdutos(String t) =>
    'nome.ilike.%$t%,descricao.ilike.%$t%,codigo.ilike.%$t%';

String filtroBuscaVendedores(String t) =>
    'nome.ilike.%$t%,codigo.ilike.%$t%';

String filtroBuscaPedidos(String t) =>
    'vendedor_nome.ilike.%$t%,cliente_nome.ilike.%$t%,'
    'cliente_nome_fantasia.ilike.%$t%,numero.ilike.%$t%';

/// `null`/'todos' = sem filtro (string vazia); senao o proprio status.
String filtroSituacao(String? s) =>
    (s == null || s.isEmpty || s == 'todos') ? '' : s;

/// Colunas de `pedidos` que a Produção usa. Fica de fora `assinatura` e
/// `assinatura_pedido` (bytea, pesadas): o detalhe busca a linha inteira.
const String colunasPedidoSemAssinatura =
    'id, numero, status, total, datahora, produtos, '
    'vendedor_codigo, vendedor_nome, '
    'cliente_id, cliente_nome, cliente_nome_fantasia, cliente_telefone, '
    'cliente_whatsapp, cliente_email, cliente_endereco, cliente_cidade, '
    'cliente_cpf_cnpj, cliente_insc_estadual, cliente_cep, cliente_anotacao, '
    'enviado_em, alterado_em, pronto_em, pronto_por, '
    'finalizado_em, finalizado_por, finalizado_manual, cancelado_em, cancelado_por, '
    'codigo_qr, etiqueta_impressa_em, etiqueta_impressa_por';

/// Mensagem em portugues para o erro de uma RPC de pedido.
String mensagemErroRpcPedido(String? code) {
  switch (code) {
    case '42501':
      return 'Sem permissão para essa ação.';
    case 'MD001':
      return 'O pedido mudou depois que a tela foi atualizada. Atualize e confira.';
    case '55000':
      return 'Esse pedido não está mais em aberto.';
    case 'P0002':
      return 'Pedido não encontrado.';
    default:
      return 'Erro ao atualizar pedido.';
  }
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

  // --------- mapeamentos DB <-> modelo (normaliza chaves) ---------
  JsonMap _produtoDbToModel(JsonMap m) => {
    'id'       : m['id'],
    'codigo'   : m['codigo'],
    'nome'     : m['nome'],
    'unidade'  : m['unidade'],
    'preco'    : m['preco'],
    'descricao': m['descricao'],
    'ativo'    : _toBool(m['ativo']),
    'datahora' : m['datahora'],
  };

  JsonMap _vendedorDbToModel(JsonMap m) => {
    'id'      : m['id'],
    'codigo'  : m['codigo'],
    'nome'    : m['nome'],
    'anotacao': m['anotacao'],
    'ativo'   : _toBool(m['ativo']),
  };

  JsonMap _clienteDbToModel(JsonMap m) => {
    'id'            : m['id'],
    'nome'          : m['nome'],
    'nome_fantasia' : m['nome_fantasia'],
    'endereco'      : m['endereco'],
    'cidade'        : m['cidade'],
    'cep'           : m['cep'],
    'cpf_cnpj'      : m['cpf_cnpj'],
    'insc_estadual' : m['insc_estadual'],
    'telefone'      : m['telefone'],
    'whatsapp'      : m['whatsapp'],
    'email'         : m['email'],
    'anotacao'      : m['anotacao'],
    'ativo'         : _toBool(m['ativo']),
    'datahora'      : m['datahora'],
    'ultimo_pedido' : m['ultimo_pedido'],
  };

  JsonMap _pedidoDbToModel(JsonMap m) => {
    'id'                    : m['id'],
    'datahora'              : m['datahora'],
    'status'                : m['status'],
    'total'                 : m['total'],
    'numero'                : m['numero'],
    'vendedor_codigo'       : m['vendedor_codigo'],
    'vendedor_nome'         : m['vendedor_nome'],
    'cliente_id'            : m['cliente_id'],
    'cliente_nome'          : m['cliente_nome'] ?? m['cliente_nome_fantasia'],
    'cliente_email'         : m['cliente_email'],
    'cliente_whatsapp'      : m['cliente_whatsapp'],
    'cliente_telefone'      : m['cliente_telefone'],
    'cliente_endereco'      : m['cliente_endereco'],
    'cliente_cidade'        : m['cliente_cidade'],
    'cliente_cpf_cnpj'      : m['cliente_cpf_cnpj'],
    'cliente_insc_estadual' : m['cliente_insc_estadual'],
    'cliente_cep'           : m['cliente_cep'],
    'cliente_anotacao'      : m['cliente_anotacao'],
    'produtos'              : m['produtos'],
    'enviado_em'            : m['enviado_em'],
    'alterado_em'           : m['alterado_em'],
    'pronto_em'             : m['pronto_em'],
    'pronto_por'            : m['pronto_por'],
    'finalizado_em'         : m['finalizado_em'],
    'finalizado_por'        : m['finalizado_por'],
    'finalizado_manual'     : m['finalizado_manual'],
    'cancelado_em'          : m['cancelado_em'],
    'cancelado_por'         : m['cancelado_por'],
    'cliente_nome_fantasia' : m['cliente_nome_fantasia'],
    'codigo_qr'             : m['codigo_qr'],
    'etiqueta_impressa_em'  : m['etiqueta_impressa_em'],
    'etiqueta_impressa_por' : m['etiqueta_impressa_por'],
  };

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
        query.or(filtroBuscaClientes(term));
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
        query.or(filtroBuscaProdutos(term));
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
        query.or(filtroBuscaVendedores(term));
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

  // ====== ESCRITA POR RPC (so admin; erros chegam como PostgrestException) ======
  Future<void> criarVendedor({
    required String codigo,
    required String nome,
    required String senha,
    String? anotacao,
    bool ativo = true,
    bool isAdmin = false,
  }) async {
    await _sb.rpc('app_criar_vendedor', params: {
      'p_codigo': codigo,
      'p_nome': nome,
      'p_senha': senha,
      'p_anotacao': anotacao,
      'p_ativo': ativo,
      'p_is_admin': isAdmin,
    });
  }

  Future<void> alterarSenhaVendedor(String codigo, String senha) async {
    await _sb.rpc('app_alterar_senha_vendedor', params: {
      'p_codigo': codigo,
      'p_senha': senha,
    });
  }

  Future<void> definirAtivoVendedor(String codigo, bool ativo) async {
    await _sb.rpc('app_definir_ativo_vendedor', params: {
      'p_codigo': codigo,
      'p_ativo': ativo,
    });
  }

  Future<void> excluirVendedor(String codigo) async {
    await _sb.rpc('app_excluir_vendedor', params: {'p_codigo': codigo});
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
        query.or(filtroBuscaPedidos(term));
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

  /// Pedidos em aberto ('salvo') e prontos para entrega ('pronto'), do mais antigo enviado para o mais novo.
  /// (Sem as colunas de assinatura: ver [colunasPedidoSemAssinatura].)
  Future<List<Pedido>> buscarPedidosEmAberto() async {
    try {
      final List<dynamic> raw = await _sb
          .from('pedidos')
          .select(colunasPedidoSemAssinatura)
          .inFilter('status', ['salvo', 'pronto'])
          .order('enviado_em', ascending: true);
      return raw
          .map((e) => Pedido.fromMap(_pedidoDbToModel(JsonMap.from(e as Map))))
          .toList();
    } catch (e) {
      throw RepoFailure('Erro ao buscar pedidos em aberto: $e');
    }
  }

  /// Parâmetros da RPC `pedido_marcar_pronto`. [alteradoEmBruto] é o texto de
  /// `alterado_em` exatamente como veio na linha (null se a linha tinha null).
  static Map<String, dynamic> paramsMarcarPronto(int id, String? alteradoEmBruto) =>
      {'p_id': id, 'p_alterado_em': alteradoEmBruto};

  Future<void> marcarPronto(int id, {String? alteradoEmBruto}) => _rpcPedido(
        'pedido_marcar_pronto',
        id,
        params: paramsMarcarPronto(id, alteradoEmBruto),
      );

  Future<void> finalizarManual(int id) => _rpcPedido('pedido_finalizar_manual', id);

  Future<void> cancelarPedido(int id) => _rpcPedido('pedido_cancelar', id);

  /// Parâmetros da RPC `pedido_marcar_etiqueta`: como em [paramsMarcarPronto],
  /// o `alterado_em` da linha de onde a etiqueta saiu (MD001 se mudou).
  static Map<String, dynamic> paramsMarcarEtiqueta(int id, String? alteradoEmBruto) =>
      {'p_id': id, 'p_alterado_em': alteradoEmBruto};

  Future<void> marcarEtiqueta(int id, {String? alteradoEmBruto}) => _rpcPedido(
        'pedido_marcar_etiqueta',
        id,
        params: paramsMarcarEtiqueta(id, alteradoEmBruto),
      );

  Future<void> _rpcPedido(String fn, int id, {Map<String, dynamic>? params}) async {
    try {
      await _sb.rpc(fn, params: params ?? {'p_id': id});
    } on PostgrestException catch (e) {
      throw RepoFailure(mensagemErroRpcPedido(e.code));
    } catch (e) {
      throw RepoFailure('Erro ao atualizar pedido: $e');
    }
  }

  /// Stream realtime (ordenado por datahora desc)
  Stream<List<Pedido>> streamPedidos() {
    return _sb
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .order('datahora', ascending: false)
        .map((rows) => rows.map((e) => Pedido.fromMap(_pedidoDbToModel(JsonMap.from(e as Map)))).toList());
  }

  Future<void> deletarPedido(int id) async {
    try {
      await _sb.from('pedidos').delete().eq('id', id);
    } catch (e) {
      throw RepoFailure('Erro ao deletar pedido: $e');
    }
  }
}
