import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/imprimir_etiqueta.dart';
import 'package:milkdim_admin/etiqueta/tamanho_etiqueta.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/models/produto.dart';
import 'package:milkdim_admin/services/supabase_service.dart' show RepoFailure;
import 'package:milkdim_ui/milkdim_ui.dart';

import 'fonte_caixas_falsa.dart';

const _copo = TipoCaixa(
    id: 1, nome: 'Copo', capacidade: 20, misturaSabores: true, ativo: true);
const _produtos = [
  Produto(id: 1, nome: 'Copo X', preco: 1, ativo: true, tipoCaixaId: 1),
];

Pedido _pedido({String status = 'pronto', int qtd = 50}) => Pedido(
      id: 7,
      numero: '7',
      status: status,
      total: 10,
      clienteNome: 'Cliente Teste',
      alteradoEmBruto: '2026-11-24T10:00:00+00:00',
      codigoQr: '11111111-1111-1111-1111-111111111111',
      itens: [PedidoItem(nome: 'Copo X', preco: 1, quantidade: qtd)],
    );

VolumesPedido _caixas(List<int> qs) => VolumesPedido(solto: false, volumes: [
      for (final q in qs)
        Volume(
            caixa: true,
            tipoNome: 'Copo',
            itens: [ItemVolume(nome: 'Copo X', quantidade: q)]),
    ]);

class _Host {
  bool? resultado;
  final marcadas = <int>[];
  final envios = <Uint8List>[];
}

FonteCaixasFalsa _fonte0({List<String>? log}) =>
    FonteCaixasFalsa(tipos: const [_copo], log: log);

Future<_Host> _abrir(
  WidgetTester tester,
  Pedido p,
  FonteCaixasFalsa fonte, {
  Size tamanho = const Size(1000, 2400),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Host();
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: FilledButton(
            onPressed: () async {
              h.resultado = await imprimirEtiquetasComVolumes(
                ctx,
                p,
                fonte: fonte,
                produtos: _produtos,
                marcar: (id, bruto) async => h.marcadas.add(id),
                enviar: (Uint8List pdf, TamanhoEtiqueta t) async {
                  h.envios.add(pdf);
                  return true;
                },
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return h;
}

/// Gerar o PDF usa assets e isolates reais: espera em tempo real até [ok].
Future<void> _esperar(WidgetTester tester, bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

int _paginas(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;

FilledButton _imprimir(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Imprimir'));

void main() {
  testWidgets('a sugestão aparece com os rótulos certos', (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    expect(find.text('Volumes do pedido 7'), findsOneWidget);
    expect(find.text('Caixa 1/3 · Copo'), findsOneWidget);
    expect(find.text('Caixa 2/3 · Copo'), findsOneWidget);
    expect(find.text('Avulsos 3/3'), findsOneWidget);
    expect(find.text('Pedido solto (sem caixas)'), findsOneWidget);
    expect(find.text('Nova caixa'), findsOneWidget);
    expect(find.text('Apagar caixa'), findsNWidgets(2));
    expect(find.text('Adicionar produto'), findsNWidgets(3));
    expect(_imprimir(tester).onPressed, isNotNull);
  });

  testWidgets('quantidade errada desabilita Imprimir e mostra "faltam"',
      (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '19');
    await tester.pump();
    expect(find.textContaining('faltam 1'), findsOneWidget);
    expect(_imprimir(tester).onPressed, isNull);
  });

  testWidgets('quantidade zero ou vazia bloqueia Imprimir mesmo se a soma bate',
      (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    // Caixa 1: 20 -> 0 e o avulso passa a ter 30: a soma continua 50.
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '0');
    await tester.enterText(find.byKey(const ValueKey('qtd-2-Copo X')), '30');
    await tester.pump();
    expect(find.textContaining('maior que zero'), findsOneWidget);
    expect(_imprimir(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '');
    await tester.pump();
    expect(_imprimir(tester).onPressed, isNull);
  });

  testWidgets('caixa acima da capacidade só avisa (amarelo) e não bloqueia',
      (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '21');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('qtd-1-Copo X')), '19');
    await tester.pump();
    final aviso = find.textContaining('cabem 20');
    expect(aviso, findsOneWidget);
    final banner = tester.widget<MdBanner>(
        find.ancestor(of: aviso, matching: find.byType(MdBanner)));
    expect(banner.tipo, MdTipo.atencao);
    expect(_imprimir(tester).onPressed, isNotNull);
  });

  testWidgets('erro de conferência aparece como banner de erro', (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '19');
    await tester.pump();
    final msg = find.textContaining('faltam 1');
    final banner = tester.widget<MdBanner>(
        find.ancestor(of: msg, matching: find.byType(MdBanner)));
    expect(banner.tipo, MdTipo.erro);
  });

  testWidgets('"Pedido solto" vira um volume só e volta ao desligar', (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Pedido solto'), findsOneWidget);
    expect(find.textContaining('Caixa '), findsNothing);
    expect(find.text('Nova caixa'), findsNothing);
    expect(_imprimir(tester).onPressed, isNotNull);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Caixa 1/3 · Copo'), findsOneWidget);
  });

  testWidgets('pedido solto: salva como solto e imprime 1 etiqueta', (tester) async {
    final fonte = _fonte0();
    final h = await _abrir(tester, _pedido(), fonte);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir'));
    await _esperar(tester, () => h.envios.isNotEmpty);
    expect(fonte.gravados.single.solto, isTrue);
    expect(fonte.gravados.single.volumes.length, 1);
    expect(_paginas(h.envios.single), 1);
  });

  testWidgets('volumes salvos que ainda batem são usados, sem aviso', (tester) async {
    await _abrir(tester, _pedido(),
        FonteCaixasFalsa(tipos: const [_copo], salvos: _caixas([25, 25])));
    expect(find.text('Caixa 1/2 · Copo'), findsOneWidget);
    expect(find.text('Caixa 2/2 · Copo'), findsOneWidget);
    expect(find.textContaining('mudou depois'), findsNothing);
  });

  testWidgets('volumes salvos que não batem mostram o aviso e a sugestão nova',
      (tester) async {
    await _abrir(tester, _pedido(),
        FonteCaixasFalsa(tipos: const [_copo], salvos: _caixas([10, 10])));
    expect(find.text('O pedido mudou depois que as caixas foram montadas.'),
        findsOneWidget);
    expect(find.text('Caixa 1/3 · Copo'), findsOneWidget);
    expect(find.text('Avulsos 3/3'), findsOneWidget);
  });

  testWidgets('Imprimir salva antes de enviar e manda 1 PDF com os N volumes',
      (tester) async {
    final fonte = _fonte0(log: []);
    final h = await _abrir(tester, _pedido(), fonte);
    await tester.tap(find.text('Imprimir'));
    await _esperar(tester, () => h.envios.isNotEmpty);
    expect(fonte.gravados.length, 1);
    expect(fonte.gravados.first.volumes.length, 3);
    expect(fonte.log, ['salvar']);
    expect(h.envios.length, 1);
    expect(_paginas(h.envios.first), 3);
    expect(find.text('As etiquetas saíram certas?'), findsOneWidget);
  });

  testWidgets('"Sim" chama marcar', (tester) async {
    final h = await _abrir(tester, _pedido(), _fonte0());
    await tester.tap(find.text('Imprimir'));
    await _esperar(tester, () => h.envios.isNotEmpty);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(h.marcadas, [7]);
    expect(h.resultado, isTrue);
  });

  testWidgets('"Imprimir de novo" com Volume 2/3 envia só esse volume e pergunta de novo',
      (tester) async {
    final h = await _abrir(tester, _pedido(), _fonte0());
    await tester.tap(find.text('Imprimir'));
    await _esperar(tester, () => h.envios.isNotEmpty);
    await tester.tap(find.text('Imprimir de novo'));
    await tester.pumpAndSettle();
    expect(find.text('Todas'), findsOneWidget);
    await tester.tap(find.textContaining('Volume 2/3'));
    await _esperar(tester, () => h.envios.length >= 2);
    expect(h.envios.length, 2);
    expect(_paginas(h.envios[1]), 1);
    expect(h.marcadas, isEmpty);
    expect(find.text('As etiquetas saíram certas?'), findsOneWidget);
    // Todas reenvia os 3.
    await tester.tap(find.text('Imprimir de novo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas'));
    await _esperar(tester, () => h.envios.length >= 3);
    expect(_paginas(h.envios[2]), 3);
  });

  testWidgets('erro em salvarVolumes mostra a mensagem e não envia', (tester) async {
    final fonte = FonteCaixasFalsa(
        tipos: const [_copo],
        falhaSalvar: RepoFailure('As caixas não batem com o pedido.'));
    final h = await _abrir(tester, _pedido(), fonte);
    await tester.tap(find.text('Imprimir'));
    await tester.pumpAndSettle();
    expect(find.text('As caixas não batem com o pedido.'), findsOneWidget);
    expect(h.envios, isEmpty);
    expect(h.resultado, isFalse);
  });

  testWidgets('finalizado com volumes salvos abre somente leitura e não salva',
      (tester) async {
    final fonte = FonteCaixasFalsa(
        tipos: const [_copo], salvos: _caixas([25, 25]), log: []);
    final h = await _abrir(tester, _pedido(status: 'finalizado'), fonte);
    expect(find.text('Caixa 1/2 · Copo'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Nova caixa'), findsNothing);
    expect(find.text('Apagar caixa'), findsNothing);
    expect(find.text('Adicionar produto'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Cancelar'), findsOneWidget);
    await tester.tap(find.text('Imprimir'));
    await _esperar(tester, () => h.envios.isNotEmpty);
    expect(fonte.gravados, isEmpty);
    expect(fonte.log, isEmpty);
    expect(h.envios.length, 1);
    expect(_paginas(h.envios.first), 2);
  });

  testWidgets('finalizado sem volumes salvos usa a etiqueta única de antes',
      (tester) async {
    final h = await _abrir(tester, _pedido(status: 'finalizado'), _fonte0());
    await _esperar(tester, () => h.envios.isNotEmpty);
    expect(find.text('Volumes do pedido 7'), findsNothing);
    expect(find.text('A etiqueta saiu certa?'), findsOneWidget);
    expect(_paginas(h.envios.first), 1);
  });

  testWidgets('cancelado não faz nada', (tester) async {
    final h = await _abrir(tester, _pedido(status: 'cancelado'), _fonte0());
    expect(find.text('Volumes do pedido 7'), findsNothing);
    expect(h.envios, isEmpty);
    expect(h.resultado, isFalse);
  });

  testWidgets('sem tipos de caixa (migração pendente): etiqueta única e aviso',
      (tester) async {
    final h =
        await _abrir(tester, _pedido(), FonteCaixasFalsa(falhaTipos: true));
    await _esperar(tester, () => h.envios.isNotEmpty);
    expect(find.text('Caixas indisponíveis; imprimindo etiqueta única.'),
        findsOneWidget);
    expect(find.text('A etiqueta saiu certa?'), findsOneWidget);
    expect(find.text('Volumes do pedido 7'), findsNothing);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(h.marcadas, [7]);
  });

  testWidgets('Cancelar na tela não salva nem envia', (tester) async {
    final fonte = _fonte0(log: []);
    final h = await _abrir(tester, _pedido(), fonte);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(fonte.log, isEmpty);
    expect(h.envios, isEmpty);
    expect(h.resultado, isFalse);
  });

  testWidgets('Nova caixa, Apagar caixa e Adicionar produto editam os volumes',
      (tester) async {
    await _abrir(tester, _pedido(), _fonte0());
    await tester.tap(find.text('Apagar caixa').first);
    await tester.pumpAndSettle();
    expect(find.text('Caixa 1/2 · Copo'), findsOneWidget);
    expect(find.textContaining('faltam 20'), findsOneWidget);
    expect(_imprimir(tester).onPressed, isNull);
    await tester.tap(find.text('Nova caixa'));
    await tester.pumpAndSettle();
    expect(find.text('Caixa 2/3 · Copo'), findsOneWidget);
    expect(find.textContaining('Caixa 2 está vazia'), findsOneWidget);
    await tester.tap(find.text('Adicionar produto').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copo X').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('qtd-1-Copo X')), '20');
    await tester.pump();
    expect(find.textContaining('faltam'), findsNothing);
    expect(_imprimir(tester).onPressed, isNotNull);
  });

  testWidgets('em 360 px a tela não estoura', (tester) async {
    await _abrir(tester, _pedido(), _fonte0(), tamanho: const Size(360, 700));
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const ValueKey('qtd-0-Copo X')), '19');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Imprimir'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });
}
