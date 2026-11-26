import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/tamanho_etiqueta.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/models/produto.dart';
import 'package:milkdim_admin/widgets/detalhe_pedido.dart';

import 'fonte_caixas_falsa.dart';

Pedido _p({
  String status = 'finalizado',
  String? por,
  String? dono = '0001',
  String? donoNome,
  String? prontoPor,
  String? canceladoPor,
  bool manual = false,
  String? codigoQr = 'qr-1',
  DateTime? impressaEm,
  String? impressaPor,
}) =>
    Pedido(
      id: 7,
      numero: '42',
      total: 10,
      status: status,
      vendedorCodigo: dono,
      vendedorNome: donoNome,
      prontoPor: prontoPor,
      canceladoPor: canceladoPor,
      finalizadoPor: por,
      finalizadoManual: manual,
      codigoQr: codigoQr,
      etiquetaImpressaEm: impressaEm,
      etiquetaImpressaPor: impressaPor,
      clienteNome: 'Cliente Teste',
      itens: const [PedidoItem(nome: 'Pudim', preco: 10, quantidade: 1)],
    );

void main() {
  group('textoEntreguePor', () {
    const nomes = {'0003': 'Vendedor Teste'};

    test('o dono', () {
      expect(textoEntreguePor(_p(por: '0001'), {'0001': 'Vendedor Teste'}),
          'Entregue por Vendedor Teste');
    });
    test('o dono sem nome na lista usa o nome gravado no pedido', () {
      expect(textoEntreguePor(_p(por: '0001', donoNome: 'Dono Teste'), const {}),
          'Entregue por Dono Teste');
    });
    test('outro vendedor com nome conhecido', () {
      expect(textoEntreguePor(_p(por: '0003'), nomes),
          'Entregue por Vendedor Teste (outro vendedor)');
    });
    test('outro vendedor sem nome', () {
      expect(textoEntreguePor(_p(por: '0009'), nomes), 'Entregue por 0009 (outro vendedor)');
    });
    test('manual', () {
      expect(textoEntreguePor(_p(por: 'admin@exemplo.test', manual: true), const {}),
          'Entregue por admin@exemplo.test (manual)');
    });
    test('nao finalizado ou sem quem', () {
      expect(textoEntreguePor(_p(status: 'pronto', por: '0001'), nomes), isNull);
      expect(textoEntreguePor(_p(por: null), nomes), isNull);
    });
  });

  group('detalhe', () {
    Future<void> abrir(WidgetTester t, Pedido p,
        {Map<String, String> nomes = const {},
        Future<Map<String, String>> Function()? buscarNomes}) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => abrirDetalhesPedido(
                ctx,
                p,
                buscar: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
                nomesPorCodigo: nomes,
                buscarNomes: buscarNomes ?? () async => const {},
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    testWidgets('pronto mostra Imprimir etiqueta e Sem etiqueta', (t) async {
      await abrir(t, _p(status: 'pronto'));
      expect(find.text('Imprimir etiqueta'), findsOneWidget);
      expect(find.text('Sem etiqueta'), findsOneWidget);
    });

    testWidgets('etiqueta impressa mostra hora e quem', (t) async {
      await abrir(
          t, _p(status: 'pronto', impressaEm: DateTime(2026, 11, 24, 9, 5), impressaPor: '0001'),
          nomes: const {'0001': 'Dona Teste'});
      expect(find.textContaining('Etiqueta impressa às'), findsOneWidget);
      expect(find.textContaining('por Dona Teste'), findsOneWidget);
    });

    testWidgets('Imprimir etiqueta no detalhe abre os volumes e completa o fluxo',
        (t) async {
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final p = _p(status: 'pronto');
      final fonte = FonteCaixasFalsa(tipos: const [
        TipoCaixa(id: 1, nome: 'Caixa teste', capacidade: 1, misturaSabores: true, ativo: true)
      ]);
      final marcadas = <int>[], envios = <Uint8List>[];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => abrirDetalhesPedido(
                ctx,
                p,
                buscar: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
                buscarNomes: () async => const {},
                fonteCaixas: fonte,
                carregarProdutos: () async => const [
                  Produto(id: 1, nome: 'Pudim', preco: 10, ativo: true, tipoCaixaId: 1)
                ],
                marcarEtiqueta: (id, bruto) async => marcadas.add(id),
                enviarParaImpressora: (Uint8List pdf, TamanhoEtiqueta tam) async {
                  envios.add(pdf);
                  return true;
                },
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Imprimir etiqueta'));
      await t.pumpAndSettle();
      expect(find.text('Volumes do pedido 42'), findsOneWidget);
      expect(find.text('Caixa 1/1 · Caixa teste'), findsOneWidget);
      await t.tap(find.text('Imprimir'));
      for (var i = 0; i < 200 && envios.isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
      expect(fonte.gravados.length, 1);
      expect(envios.length, 1);
      expect(
          RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(envios.first)).length, 1);
      await t.tap(find.text('Sim'));
      await t.pumpAndSettle();
      expect(marcadas, [7]);
    });

    testWidgets(
        'finalizado: Reimprimir etiqueta abre somente leitura e o Sim não marca',
        (t) async {
      t.view.physicalSize = const Size(1000, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final p = _p(status: 'finalizado');
      final fonte = FonteCaixasFalsa(
        tipos: const [
          TipoCaixa(id: 1, nome: 'Caixa teste', capacidade: 1, misturaSabores: true, ativo: true)
        ],
        salvos: const VolumesPedido(solto: false, volumes: [
          Volume(caixa: true, tipoNome: 'Caixa teste', itens: [
            ItemVolume(nome: 'Pudim', quantidade: 1),
          ]),
        ]),
        log: [],
      );
      final marcadas = <int>[], envios = <Uint8List>[];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => abrirDetalhesPedido(
                ctx,
                p,
                buscar: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
                buscarNomes: () async => const {},
                fonteCaixas: fonte,
                carregarProdutos: () async => const [
                  Produto(id: 1, nome: 'Pudim', preco: 10, ativo: true, tipoCaixaId: 1)
                ],
                marcarEtiqueta: (id, bruto) async => marcadas.add(id),
                enviarParaImpressora: (Uint8List pdf, TamanhoEtiqueta tam) async {
                  envios.add(pdf);
                  return true;
                },
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text('Imprimir etiqueta'), findsNothing);
      await t.tap(find.text('Reimprimir etiqueta'));
      await t.pumpAndSettle();
      expect(find.text('Volumes do pedido 42'), findsOneWidget);
      expect(find.text('Nova caixa'), findsNothing);
      await t.tap(find.text('Imprimir'));
      for (var i = 0; i < 200 && envios.isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
      expect(envios.length, 1);
      await t.tap(find.text('Sim'));
      await t.pumpAndSettle();
      expect(marcadas, isEmpty);
      expect(fonte.log, isEmpty);
      expect(find.text('As etiquetas saíram certas?'), findsNothing);
    });

    testWidgets('finalizado sem codigo_qr: Reimprimir etiqueta desabilitado', (t) async {
      await abrir(t, _p(status: 'finalizado', codigoQr: null));
      final b = t.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Reimprimir etiqueta'));
      expect(b.onPressed, isNull);
    });

    testWidgets('sem codigo_qr o botao fica desabilitado', (t) async {
      await abrir(t, _p(status: 'pronto', codigoQr: null));
      final b = t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Imprimir etiqueta'));
      expect(b.onPressed, isNull);
    });

    testWidgets('em aberto nao mostra o botao; entregue mostra quem entregou', (t) async {
      await abrir(t, _p(status: 'salvo'));
      expect(find.text('Imprimir etiqueta'), findsNothing);
    });

    testWidgets('entregue mostra Entregue por', (t) async {
      await abrir(t, _p(por: '0003'), nomes: const {'0003': 'Vendedor Teste'});
      expect(find.text('Entregue por Vendedor Teste (outro vendedor)'), findsOneWidget);
    });

    testWidgets('Pronto por, Finalizado por e Cancelado por mostram o nome', (t) async {
      await abrir(t, _p(por: '0003', prontoPor: '0001', canceladoPor: '0002'),
          nomes: const {'0001': 'Dona Teste', '0002': 'Outra Teste', '0003': 'Vendedor Teste'});
      // A seção Situação fica no fim da folha (ListView): rola até ela.
      await t.scrollUntilVisible(find.text('Outra Teste'), 300,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Dona Teste'), findsOneWidget);
      expect(find.text('Vendedor Teste (outro vendedor)'), findsOneWidget);
      expect(find.text('Outra Teste'), findsOneWidget);
    });

    testWidgets('sem a lista de nomes (aba Produção), busca os nomes ao abrir', (t) async {
      var buscou = 0;
      await abrir(t, _p(por: '0003'), buscarNomes: () async {
        buscou++;
        return const {'0003': 'Vendedor Teste'};
      });
      expect(buscou, 1);
      expect(find.text('Entregue por Vendedor Teste (outro vendedor)'), findsOneWidget);
    });
  });
}
