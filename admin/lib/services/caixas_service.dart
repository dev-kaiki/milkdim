// Tipos de caixa e volumes (caixas) dos pedidos.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../etiqueta/volumes.dart';
import 'supabase_service.dart' show RepoFailure;

abstract class FonteCaixas {
  Future<List<TipoCaixa>> tiposCaixa();
  Future<void> criarTipo(String nome, int capacidade, bool mistura);
  Future<void> alterarTipo(TipoCaixa t);
  Future<VolumesPedido?> volumesSalvos(int pedidoId);
  Future<void> salvarVolumes(int pedidoId, VolumesPedido v);
  Future<void> definirTipoDoProduto(int produtoId, int? tipoId);
}

class CaixasService implements FonteCaixas {
  final SupabaseClient _sb;
  CaixasService([SupabaseClient? injected])
      : _sb = injected ?? Supabase.instance.client;

  static String mensagemErroCaixas(String? code) {
    switch (code) {
      case 'MD010':
        return 'Este pedido não pode ter as caixas alteradas.';
      case 'MD011':
        return 'As caixas não batem com o pedido.';
      case '23505':
        return 'Já existe um tipo de caixa com esse nome.';
      case '42501':
        return 'Sem permissão para essa ação.';
      default:
        return 'Erro ao salvar as caixas.';
    }
  }

  static Map<String, dynamic> paramsSalvarVolumes(int id, VolumesPedido v) => {
        'p_id': id,
        'p_solto': v.solto,
        'p_volumes': [for (final x in v.volumes) x.toJson()],
      };

  /// Atualiza só o tipo, com null explícito: Produto.toSupabase descarta
  /// valores nulos e por isso nunca limparia o tipo.
  static Map<String, dynamic> paramsTipoDoProduto(int? tipoId) =>
      {'tipo_caixa_id': tipoId};

  Future<T> _run<T>(Future<T> Function() f, String leitura,
      {bool escrita = false}) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw RepoFailure(
          escrita ? mensagemErroCaixas(e.code) : '$leitura: ${e.message}');
    } catch (e) {
      throw RepoFailure(escrita ? 'Erro ao salvar as caixas.' : '$leitura: $e');
    }
  }

  @override
  Future<List<TipoCaixa>> tiposCaixa() => _run(() async {
        final raw =
            await _sb.from('tipos_caixa').select().order('nome', ascending: true);
        return [
          for (final e in (raw as List))
            TipoCaixa.fromMap(Map<String, dynamic>.from(e as Map))
        ];
      }, 'Erro ao buscar tipos de caixa');

  @override
  Future<void> criarTipo(String nome, int capacidade, bool mistura) =>
      _run(() async {
        await _sb.from('tipos_caixa').insert({
          'nome': nome.trim(),
          'capacidade': capacidade,
          'mistura_sabores': mistura,
        });
      }, 'Erro ao criar tipo', escrita: true);

  @override
  Future<void> alterarTipo(TipoCaixa t) => _run(() async {
        await _sb.from('tipos_caixa').update({
          'nome': t.nome.trim(),
          'capacidade': t.capacidade,
          'mistura_sabores': t.misturaSabores,
          'ativo': t.ativo,
        }).eq('id', t.id);
      }, 'Erro ao alterar tipo', escrita: true);

  @override
  Future<VolumesPedido?> volumesSalvos(int pedidoId) => _run(() async {
        final row = await _sb
            .from('pedido_volumes')
            .select('solto, volumes')
            .eq('pedido_id', pedidoId)
            .maybeSingle();
        if (row == null) return null;
        return VolumesPedido(
          solto: row['solto'] == true,
          volumes: [
            for (final e in (row['volumes'] as List? ?? const []))
              Volume.fromJson(Map<String, dynamic>.from(e as Map))
          ],
        );
      }, 'Erro ao buscar as caixas');

  @override
  Future<void> salvarVolumes(int pedidoId, VolumesPedido v) => _run(() async {
        await _sb.rpc('pedido_salvar_volumes',
            params: paramsSalvarVolumes(pedidoId, v));
      }, 'Erro ao salvar as caixas', escrita: true);

  @override
  Future<void> definirTipoDoProduto(int produtoId, int? tipoId) =>
      _run(() async {
        await _sb
            .from('produtos')
            .update(paramsTipoDoProduto(tipoId))
            .eq('id', produtoId);
      }, 'Erro ao definir o tipo', escrita: true);
}
