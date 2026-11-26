import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/models/produto.dart';
import 'package:milkdim_admin/services/caixas_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart';

void main() {
  test('mensagemErroCaixas por codigo', () {
    expect(CaixasService.mensagemErroCaixas('MD010'),
        'Este pedido não pode ter as caixas alteradas.');
    expect(CaixasService.mensagemErroCaixas('MD011'),
        'As caixas não batem com o pedido.');
    expect(CaixasService.mensagemErroCaixas('23505'),
        'Já existe um tipo de caixa com esse nome.');
    expect(CaixasService.mensagemErroCaixas('42501'),
        'Sem permissão para essa ação.');
    expect(CaixasService.mensagemErroCaixas('22023'), 'Erro ao salvar as caixas.');
    expect(CaixasService.mensagemErroCaixas(null), 'Erro ao salvar as caixas.');
  });

  test('paramsSalvarVolumes monta o formato da RPC', () {
    const v = VolumesPedido(solto: false, volumes: [
      Volume(
          caixa: true,
          tipoNome: 'Pote',
          itens: [ItemVolume(nome: 'Pote A', quantidade: 16)]),
      Volume(
          caixa: false,
          tipoNome: null,
          itens: [ItemVolume(nome: 'X', quantidade: 2)]),
    ]);
    expect(CaixasService.paramsSalvarVolumes(7, v), {
      'p_id': 7,
      'p_solto': false,
      'p_volumes': [
        {
          'tipo': 'caixa',
          'caixa': 'Pote',
          'itens': [
            {'nome': 'Pote A', 'quantidade': 16}
          ]
        },
        {
          'tipo': 'avulso',
          'caixa': null,
          'itens': [
            {'nome': 'X', 'quantidade': 2}
          ]
        },
      ],
    });
  });

  test('Produto.fromMap le tipo_caixa_id e toSupabase o leva', () {
    final p = Produto.fromMap({'id': 1, 'nome': 'A', 'tipo_caixa_id': 3});
    expect(p.tipoCaixaId, 3);
    expect(p.toSupabase()['tipo_caixa_id'], 3);
    expect(Produto.fromMap({'id': 1, 'nome': 'A'}).tipoCaixaId, isNull);
  });

  test('leitura de produto do banco carrega tipo_caixa_id', () {
    final m = produtoDbParaModelo(
        {'id': 1, 'nome': 'A', 'ativo': true, 'tipo_caixa_id': 5});
    expect(Produto.fromMap(m).tipoCaixaId, 5);
    expect(Produto.fromMap(produtoDbParaModelo({'id': 1, 'nome': 'A'})).tipoCaixaId,
        isNull);
  });

  test('paramsTipoDoProduto envia null explicito', () {
    expect(CaixasService.paramsTipoDoProduto(null), {'tipo_caixa_id': null});
    expect(CaixasService.paramsTipoDoProduto(2), {'tipo_caixa_id': 2});
  });
}
