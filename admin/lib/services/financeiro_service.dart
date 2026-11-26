// lib/services/financeiro_service.dart
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../financeiro/modelos_financeiro.dart';
import '../models/pedido.dart';
import 'supabase_service.dart';

/// Fonte de dados do financeiro (a tela depende disto, não do Supabase).
abstract class FonteFinanceiro {
  Future<List<Pedido>> pedidosEntregues(DateTime inicioLocal, DateTime fimLocal);
  Future<List<Pedido>> pedidosProntos();
  Future<List<Saida>> saidasEntre(DateTime inicioLocal, DateTime fimLocal);
  Future<List<CategoriaSaida>> categorias();
  Future<void> inserirSaida(Saida s);
  Future<void> alterarSaida(Saida s);
  Future<void> apagarSaida(int id);
  Future<void> criarCategoria(String nome);
  Future<void> renomearCategoria(int id, String nome);
  Future<void> definirCategoriaAtiva(int id, bool ativa);
}

/// Mensagem em português para erros do banco nas tabelas do financeiro.
String mensagemErroFinanceiro(String? code) {
  switch (code) {
    case '23505':
      return 'Já existe uma categoria com esse nome.';
    case '23503':
      return 'Essa categoria tem saídas; desative em vez de apagar.';
    case '42501':
      return 'Sem permissão para essa ação.';
    default:
      return 'Erro ao acessar o financeiro.';
  }
}

class FinanceiroService implements FonteFinanceiro {
  final SupabaseClient _sb;
  FinanceiroService([SupabaseClient? injected])
      : _sb = injected ?? Supabase.instance.client;

  static const _bloco = 1000;

  /// Bordas locais -> texto ISO em UTC para `gte`/`lt` em `finalizado_em`.
  static ({String de, String ate}) filtroEntregues(
          DateTime inicioLocal, DateTime fimLocal) =>
      (
        de: inicioLocal.toUtc().toIso8601String(),
        ate: fimLocal.toUtc().toIso8601String(),
      );

  /// Bordas locais -> 'yyyy-MM-dd' para `gte`/`lt` em `data`.
  static ({String de, String ate}) filtroSaidas(
      DateTime inicioLocal, DateTime fimLocal) {
    final f = DateFormat('yyyy-MM-dd');
    return (de: f.format(inicioLocal), ate: f.format(fimLocal));
  }

  Future<T> _run<T>(String acao, Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw RepoFailure(mensagemErroFinanceiro(e.code));
    } catch (e) {
      throw RepoFailure('Erro ao $acao: $e');
    }
  }

  Pedido _pedido(dynamic e) =>
      Pedido.fromMap(pedidoDbParaModelo(JsonMap.from(e as Map)));

  @override
  Future<List<Pedido>> pedidosEntregues(
      DateTime inicioLocal, DateTime fimLocal) {
    final f = filtroEntregues(inicioLocal, fimLocal);
    return _run('buscar pedidos entregues', () async {
      final out = <Pedido>[];
      var i = 0;
      while (true) {
        final List<dynamic> raw = await _sb
            .from('pedidos')
            .select(colunasPedidoSemAssinatura)
            .eq('status', 'finalizado')
            .gte('finalizado_em', f.de)
            .lt('finalizado_em', f.ate)
            .order('finalizado_em', ascending: true)
            .order('id', ascending: true)
            .range(i, i + _bloco - 1);
        out.addAll(raw.map(_pedido));
        if (raw.length < _bloco) break;
        i += _bloco;
      }
      return out;
    });
  }

  @override
  Future<List<Pedido>> pedidosProntos() => _run('buscar pedidos prontos', () async {
        final List<dynamic> raw = await _sb
            .from('pedidos')
            .select(colunasPedidoSemAssinatura)
            .eq('status', 'pronto');
        return raw.map(_pedido).toList();
      });

  @override
  Future<List<Saida>> saidasEntre(DateTime inicioLocal, DateTime fimLocal) {
    final f = filtroSaidas(inicioLocal, fimLocal);
    return _run('buscar saídas', () async {
      final out = <Saida>[];
      var i = 0;
      while (true) {
        final List<dynamic> raw = await _sb
            .from('saidas')
            .select()
            .gte('data', f.de)
            .lt('data', f.ate)
            .order('data', ascending: false)
            .order('id', ascending: false)
            .range(i, i + _bloco - 1);
        out.addAll(raw.map((e) => Saida.fromMap(JsonMap.from(e as Map))));
        if (raw.length < _bloco) break;
        i += _bloco;
      }
      return out;
    });
  }

  @override
  Future<List<CategoriaSaida>> categorias() => _run('buscar categorias', () async {
        final List<dynamic> raw = await _sb
            .from('categorias_saida')
            .select()
            .order('ordem', ascending: true)
            .order('nome', ascending: true);
        return raw
            .map((e) => CategoriaSaida.fromMap(JsonMap.from(e as Map)))
            .toList();
      });

  @override
  Future<void> inserirSaida(Saida s) => _run('lançar saída', () async {
        await _sb.from('saidas').insert(s.toGravar());
      });

  @override
  Future<void> alterarSaida(Saida s) => _run('alterar saída', () async {
        await _sb.from('saidas').update(s.toGravar()).eq('id', s.id!);
      });

  @override
  Future<void> apagarSaida(int id) => _run('apagar saída', () async {
        await _sb.from('saidas').delete().eq('id', id);
      });

  @override
  Future<void> criarCategoria(String nome) => _run('criar categoria', () async {
        final List<dynamic> u = await _sb
            .from('categorias_saida')
            .select('ordem')
            .order('ordem', ascending: false)
            .limit(1);
        final prox = u.isEmpty ? 1 : ((u.first as Map)['ordem'] as num).toInt() + 1;
        await _sb.from('categorias_saida').insert({'nome': nome, 'ordem': prox});
      });

  @override
  Future<void> renomearCategoria(int id, String nome) =>
      _run('renomear categoria', () async {
        await _sb.from('categorias_saida').update({'nome': nome}).eq('id', id);
      });

  @override
  Future<void> definirCategoriaAtiva(int id, bool ativa) =>
      _run('atualizar categoria', () async {
        await _sb.from('categorias_saida').update({'ativa': ativa}).eq('id', id);
      });
}
