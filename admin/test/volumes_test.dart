import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/models/produto.dart';

PedidoItem item(String nome, int q) =>
    PedidoItem(nome: nome, preco: 1, quantidade: q);

const pote = TipoCaixa(
    id: 1, nome: 'Pote', capacidade: 16, misturaSabores: true, ativo: true);
const copo = TipoCaixa(
    id: 2, nome: 'Copo', capacidade: 20, misturaSabores: true, ativo: true);
const copoSemMistura = TipoCaixa(
    id: 2, nome: 'Copo', capacidade: 20, misturaSabores: false, ativo: true);

List<String> rotulos(VolumesPedido v) =>
    [for (var i = 0; i < v.volumes.length; i++) rotuloVolume(v, i)];

Map<String, int> qtds(Volume v) =>
    {for (final i in v.itens) i.nome: i.quantidade};

void main() {
  test('50 copos de um sabor: 2 caixas e 10 avulsos', () {
    final v = sugerirVolumes(
        [item('Copo leite', 50)], {chaveNome('Copo leite'): copo});
    expect(v.solto, false);
    expect(rotulos(v), ['Caixa 1/3 · Copo', 'Caixa 2/3 · Copo', 'Avulsos 3/3']);
    expect(v.volumes[2].caixa, false);
    expect(qtds(v.volumes[2]), {'Copo leite': 10});
  });

  test('mistura ligada atravessa sabores', () {
    final tipos = {chaveNome('Leite'): copo, chaveNome('Doce'): copo};
    final v = sugerirVolumes([item('Leite', 30), item('Doce', 20)], tipos);
    expect(qtds(v.volumes[0]), {'Leite': 20});
    expect(qtds(v.volumes[1]), {'Leite': 10, 'Doce': 10});
    expect(v.volumes[1].itens.map((e) => e.nome), ['Leite', 'Doce']);
    expect(v.volumes[2].caixa, false);
    expect(qtds(v.volumes[2]), {'Doce': 10});
  });

  test('mistura desligada: cada produto só nas próprias caixas', () {
    final tipos = {
      chaveNome('Leite'): copoSemMistura,
      chaveNome('Doce'): copoSemMistura
    };
    final v = sugerirVolumes([item('Leite', 30), item('Doce', 20)], tipos);
    expect(v.volumes.length, 3);
    expect(qtds(v.volumes[0]), {'Leite': 20});
    expect(qtds(v.volumes[1]), {'Doce': 20});
    expect(v.volumes[2].caixa, false);
    expect(qtds(v.volumes[2]), {'Leite': 10});
  });

  test('tipos na ordem do primeiro item; avulsos por último', () {
    final tipos = {
      chaveNome('pote x'): pote,
      chaveNome('copo x'): copo,
      chaveNome('grande'): null,
    };
    final v = sugerirVolumes(
        [item('pote x', 16), item('copo x', 20), item('grande', 2)], tipos);
    expect(rotulos(v), ['Caixa 1/3 · Pote', 'Caixa 2/3 · Copo', 'Avulsos 3/3']);
    expect(qtds(v.volumes[2]), {'grande': 2});
  });

  test('sem avulsos, n conta só as caixas', () {
    final v = sugerirVolumes([item('Copo', 40)], {chaveNome('Copo'): copo});
    expect(rotulos(v), ['Caixa 1/2 · Copo', 'Caixa 2/2 · Copo']);
  });

  test('só produtos sem caixa vira Avulsos 1/1', () {
    final v = sugerirVolumes([item('Outro', 3)], {});
    expect(rotulos(v), ['Avulsos 1/1']);
    expect(qtds(v.volumes[0]), {'Outro': 3});
  });

  test('pedido solto: um volume com tudo e rótulo Pedido solto', () {
    final v = pedidoSolto([item('A', 2), item('B', 3)]);
    expect(v.solto, true);
    expect(v.volumes.length, 1);
    expect(v.volumes[0].caixa, false);
    expect(qtds(v.volumes[0]), {'A': 2, 'B': 3});
    expect(rotuloVolume(v, 0), 'Pedido solto');
  });

  test('mesmo produto em duas linhas soma por nome', () {
    final v = sugerirVolumes(
        [item('Copo', 12), item('Copo', 12)], {chaveNome('Copo'): copo});
    expect(rotulos(v), ['Caixa 1/2 · Copo', 'Avulsos 2/2']);
    expect(qtds(v.volumes[1]), {'Copo': 4});
  });

  test('itens com quantidade <= 0 são ignorados', () {
    final v = sugerirVolumes([item('A', 0), item('B', -2), item('C', 1)], {});
    expect(qtds(v.volumes[0]), {'C': 1});
  });

  test('nome com maiúsculas e espaços liga ao produto', () {
    final map = tiposPorNomeDeProduto([
      const Produto(
          id: 1, nome: 'Copo leite 160g', preco: 1, ativo: true, tipoCaixaId: 2)
    ], [
      copo
    ]);
    final v = sugerirVolumes([item(' COPO leite 160g ', 20)], map);
    expect(rotulos(v), ['Caixa 1/1 · Copo']);
    // nome do item no volume vai como veio no pedido
    expect(v.volumes[0].itens.single.nome, ' COPO leite 160g ');
  });

  test('produto repetido: vale o ativo de menor id', () {
    final map = tiposPorNomeDeProduto([
      const Produto(id: 1, nome: 'X', preco: 1, ativo: false, tipoCaixaId: 2),
      const Produto(id: 5, nome: 'x', preco: 1, ativo: true, tipoCaixaId: 2),
      const Produto(id: 3, nome: 'X ', preco: 1, ativo: true, tipoCaixaId: 1),
    ], [
      pote,
      copo
    ]);
    expect(map['x'], pote);
    final soInativos = tiposPorNomeDeProduto([
      const Produto(id: 9, nome: 'Y', preco: 1, ativo: false, tipoCaixaId: 2),
      const Produto(id: 4, nome: 'Y', preco: 1, ativo: false, tipoCaixaId: 1),
    ], [
      pote,
      copo
    ]);
    expect(soInativos['y'], pote);
    final semTipo = tiposPorNomeDeProduto(
        [const Produto(id: 1, nome: 'Z', preco: 1, ativo: true)], [pote]);
    expect(semTipo.containsKey('z'), true);
    expect(semTipo['z'], isNull);
  });

  test('tipo inativo vai para avulsos', () {
    const inativo = TipoCaixa(
        id: 7,
        nome: 'Velho',
        capacidade: 5,
        misturaSabores: true,
        ativo: false);
    final map = tiposPorNomeDeProduto([
      const Produto(id: 1, nome: 'W', preco: 1, ativo: true, tipoCaixaId: 7)
    ], [
      inativo
    ]);
    expect(map['w'], isNull);
    final v = sugerirVolumes([item('W', 10)], map);
    expect(rotulos(v), ['Avulsos 1/1']);
  });

  test('conferirVolumes aponta faltam/sobram/caixa vazia', () {
    final itens = [item('Copo X', 10), item('Pote Y', 5)];
    const v = VolumesPedido(solto: false, volumes: [
      Volume(caixa: true, tipoNome: 'Copo', itens: [
        ItemVolume(nome: 'Copo X', quantidade: 7),
        ItemVolume(nome: 'Pote Y', quantidade: 7),
      ]),
      Volume(caixa: true, tipoNome: 'Copo', itens: []),
      Volume(caixa: false, tipoNome: null, itens: []),
    ]);
    expect(conferirVolumes(itens, v), [
      'Copo X: faltam 3',
      'Pote Y: sobram 2',
      'Caixa 2/3 · Copo está vazia',
      'Avulsos 3/3 está vazio',
    ]);
    final ok = sugerirVolumes(itens, {});
    expect(conferirVolumes(itens, ok), isEmpty);
  });

  test('volumesValem falso quando o pedido mudou', () {
    final itens = [item('A', 5)];
    final salvos = sugerirVolumes(itens, {});
    expect(volumesValem(itens, salvos), true);
    expect(volumesValem([item('A', 6)], salvos), false);
    expect(volumesValem([item('A', 5), item('B', 1)], salvos), false);
  });

  test('conferência soma por nome com trim, como o servidor', () {
    final itens = [item('Copo', 5), item(' Copo ', 5)];
    const v = VolumesPedido(solto: true, volumes: [
      Volume(
          caixa: false,
          tipoNome: null,
          itens: [ItemVolume(nome: 'Copo', quantidade: 10)])
    ]);
    expect(conferirVolumes(itens, v), isEmpty);
    const v2 = VolumesPedido(solto: true, volumes: [
      Volume(
          caixa: false,
          tipoNome: null,
          itens: [ItemVolume(nome: 'copo', quantidade: 10)])
    ]);
    expect(conferirVolumes(itens, v2), ['Copo: faltam 10', 'copo: sobram 10']);
  });

  test('avisosCapacidade não bloqueia', () {
    const v = VolumesPedido(solto: false, volumes: [
      Volume(caixa: true, tipoNome: 'Copo', itens: [
        ItemVolume(nome: 'A', quantidade: 12),
        ItemVolume(nome: 'B', quantidade: 10),
      ]),
      Volume(caixa: true, tipoNome: 'Copo', itens: [
        ItemVolume(nome: 'A', quantidade: 20)
      ]),
      Volume(caixa: false, tipoNome: null, itens: [
        ItemVolume(nome: 'C', quantidade: 99)
      ]),
    ]);
    expect(avisosCapacidade(v, {'Copo': copo}),
        ['Caixa 1/3 tem 22 unidades (cabem 20)']);
  });

  test('Volume.toJson/fromJson ida e volta', () {
    const caixa = Volume(
        caixa: true,
        tipoNome: 'Copo',
        itens: [ItemVolume(nome: 'A', quantidade: 3)]);
    expect(caixa.toJson(), {
      'tipo': 'caixa',
      'caixa': 'Copo',
      'itens': [
        {'nome': 'A', 'quantidade': 3}
      ]
    });
    final de = Volume.fromJson(caixa.toJson());
    expect(de.caixa, true);
    expect(de.tipoNome, 'Copo');
    expect(de.itens.single.nome, 'A');
    expect(de.itens.single.quantidade, 3);

    const avulso = Volume(
        caixa: false,
        tipoNome: null,
        itens: [ItemVolume(nome: 'B', quantidade: 1)]);
    expect(avulso.toJson()['tipo'], 'avulso');
    expect(avulso.toJson()['caixa'], isNull);
    expect(Volume.fromJson(avulso.toJson()).caixa, false);
  });

  test('TipoCaixa.fromMap e Produto.tipoCaixaId aceitam int, num e texto', () {
    final t = TipoCaixa.fromMap({
      'id': '3',
      'nome': 'Médio',
      'capacidade': 4.0,
      'mistura_sabores': true,
      'ativo': false,
    });
    expect(t.id, 3);
    expect(t.capacidade, 4);
    expect(t.misturaSabores, true);
    expect(t.ativo, false);
    Produto p(dynamic v) => Produto.fromMap(
        {'id': 1, 'nome': 'a', 'preco': 1, 'tipo_caixa_id': v});
    expect(p(2).tipoCaixaId, 2);
    expect(p('2').tipoCaixaId, 2);
    expect(p(null).tipoCaixaId, isNull);
  });
}
