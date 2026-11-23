// test/telas_pronto_assinaturas_test.dart
//
// Fase A.2 nas telas do vendedor: enviar o pedido com a assinatura do pedido,
// salvar alterações (nova assinatura só quando mudam itens ou cliente),
// registrar a entrega com a assinatura da entrega, o selo "Pronto" em Meus
// pedidos e o PDF com as duas assinaturas. Dados falsos.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:milkdim_app/pages/pedido_page.dart';
import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/db.dart' show kLimparAssinaturaPedido;
import 'package:milkdim_app/utils/pdf_utils.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';
import 'package:milkdim_app/utils/produto.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';
import 'package:milkdim_app/widgets/pedido_ui.dart';

/// PNG 1x1 de verdade (a tela mostra a assinatura com Image.memory).
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
final String _hex0x = '0x${cvt.hex.encode(_png)}';

const _vendedor = <String, dynamic>{'codigo': '0003', 'nome': 'Vendedor Teste'};

/// Catálogo de hoje: o Leite ninho subiu de preço e o "Doce antigo" saiu.
const _catalogo = <Produto>[
  Produto(id: 1, nome: 'Leite ninho', preco: 11.5),
  Produto(id: 2, nome: 'Pudim', preco: 0.1),
];

/// Itens como o servidor guardou (jsonb): preço antigo, item fora do catálogo,
/// chave a mais e subtotal com ruído.
const _itensGuardados =
    '[{"nome":"Leite ninho","subtotal":32.7,"preco":10.9,"quantidade":3,"unidade":"un"},'
    '{"nome":"Pudim","subtotal":0.30000000000000004,"preco":0.1,"quantidade":3},'
    '{"nome":"Doce antigo","preco":7.25,"quantidade":2,"subtotal":14.5}]';

Map<String, dynamic> _pedidoGuardado({
  String status = 'pronto',
  bool assinado = true,
  String clienteNome = 'Padaria Central ',
}) =>
    {
      'id': 42,
      'numero': '70',
      'status': status,
      'so_local': 0,
      'pendente_envio': 0,
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor Teste',
      'datahora': '2026-11-23T09:00:00+00:00',
      'enviado_em': '2026-11-23T09:00:01+00:00',
      'total': 47.5,
      'cliente_id': 7,
      'cliente_nome': clienteNome,
      'produtos': _itensGuardados,
      if (assinado) 'assinatura_pedido': _hex0x,
    };

/// O que a tela pediu e gravou.
class _Espiao {
  final pedidos = <(TipoAssinatura, String?)>[];
  final gravados = <Map<String, dynamic>>[];
  Uint8List? resposta;
  ResultadoGravacao resultado = ResultadoGravacao.enviado;

  Future<Uint8List?> pedir(TipoAssinatura tipo, {String? aviso}) async {
    pedidos.add((tipo, aviso));
    return resposta;
  }

  Future<ResultadoGravacao> gravar(Map<String, dynamic> pedido, {required bool novo}) async {
    gravados.add(Map<String, dynamic>.from(pedido));
    return resultado;
  }
}

/// Abre [pagina] por cima de uma tela inicial (a página fecha com pop).
Future<void> _abrir(WidgetTester tester, Widget pagina) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => pagina)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _abrirResumoETocar(WidgetTester tester, String botao) async {
  await tester
      .tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(botao));
  await tester.pumpAndSettle();
  await tester.tap(find.text(botao));
  await tester.pumpAndSettle();
}

/// Abre o resumo, toca "Assinar" (o espião responde) e fecha a folha.
Future<void> _assinarNoResumoEFechar(WidgetTester tester) async {
  await tester
      .tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Assinar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Assinar'));
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(400, 10)); // fora da folha
  await tester.pumpAndSettle();
  expect(find.text('Resumo do Pedido'), findsNothing);
}

Future<void> _preencherPedidoNovo(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Padaria Central');
  await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '2');
  await tester.pumpAndSettle();
}

void main() {
  group('regras (rulings 5a, 5b, 5c)', () {
    test('mesmosItens compara preco e quantidade exatos; ruido so no subtotal', () {
      final a = [
        {'nome': 'Pudim', 'preco': 18.9, 'quantidade': 2, 'subtotal': 37.8},
      ];
      expect(
          mesmosItens(a, [
            {'nome': 'Pudim', 'preco': 18.900000000000002, 'quantidade': 2, 'subtotal': 37.8},
          ]),
          isFalse,
          reason: 'o servidor compara o jsonb: preço diferente é outro pedido');
      expect(
          mesmosItens(a, [
            {'nome': 'Pudim', 'preco': 18.9, 'quantidade': 2.0001, 'subtotal': 37.8},
          ]),
          isFalse);
      expect(
          mesmosItens(a, [
            {'nome': 'Pudim ', 'preco': 18.9, 'quantidade': 2.0, 'subtotal': 18.9 * 2},
          ]),
          isTrue,
          reason: '2 e 2.0 são o mesmo número; subtotal não conta');
    });

    test('so o caminho sem arquivo nao conta como assinatura do pedido', () {
      final original = {
        'so_local': 0,
        'cliente_id': 7,
        'cliente_nome': 'Padaria Central',
        'produtos': '[]',
        'assinatura_pedido_path': '/sig/ped_70.png',
      };
      expect(
          precisaAssinaturaDoPedido(
              original: original, editado: original, arquivoExiste: (_) => false),
          isTrue);
      expect(
          precisaAssinaturaDoPedido(
              original: original, editado: original, arquivoExiste: (p) => p == '/sig/ped_70.png'),
          isFalse);
      expect(temAssinaturaDoPedido({'assinatura_pedido': _hex0x}, arquivoExiste: (_) => false),
          isTrue);
      expect(temAssinaturaDoPedido({'assinatura_pedido': '0x'}), isFalse);
      expect(temAssinaturaDoPedido({'assinatura_pedido': Uint8List(0)}), isFalse);
    });

    test('padrao le o arquivo do aparelho', () async {
      final dir = await Directory.systemTemp.createTemp('telas_pronto');
      final arq = File('${dir.path}/ped.png')..writeAsBytesSync(_png);
      expect(temAssinaturaDoPedido({'assinatura_pedido_path': arq.path}), isTrue);
      expect(temAssinaturaDoPedido({'assinatura_pedido_path': '${dir.path}/nao.png'}), isFalse);
      await dir.delete(recursive: true);
    });

    test('cliente_nome com espacos ou nulo nao conta como mudanca', () {
      final antes = {'cliente_id': 7, 'cliente_nome': ' Padaria Central ', 'produtos': '[]'};
      expect(itensOuClienteMudaram(antes, {...antes, 'cliente_nome': 'Padaria Central'}), isFalse);
      expect(
          itensOuClienteMudaram({...antes, 'cliente_nome': null}, {...antes, 'cliente_nome': ''}),
          isFalse);
      expect(itensOuClienteMudaram(antes, {...antes, 'cliente_nome': 'Padaria Nova'}), isTrue);
    });

    test('pedidoDaTela manda o cliente_nome guardado quando so mudam espacos', () {
      Map<String, dynamic> daTela(Map<String, dynamic> base, String nome) => pedidoDaTela(
            base: base,
            numero: '70',
            produtos: (jsonDecode(_itensGuardados) as List).cast<Map<String, dynamic>>(),
            total: 0,
            status: 'pronto',
            datahora: '2026-11-23T11:00:00.000Z',
            clienteId: 7,
            cliente: {'cliente_nome': nome},
            assinatura: null,
            assinaturaPath: null,
          );
      final base = _pedidoGuardado();
      expect(daTela(base, 'Padaria Central')['cliente_nome'], 'Padaria Central ',
          reason: 'o servidor compara o valor cru');
      expect(daTela(base, 'Padaria Central')['status'], 'pronto');
      expect(daTela({...base, 'cliente_nome': null}, '')['cliente_nome'], isNull);
      expect(daTela(base, 'Padaria Nova')['cliente_nome'], 'Padaria Nova');
      expect(daTela(base, 'Padaria Nova')['status'], 'salvo');
    });

    test('aviso da assinatura do pedido', () {
      final assinado = _pedidoGuardado();
      final mudou = {...assinado, 'cliente_id': 8};
      expect(avisoAssinaturaDoPedido(original: assinado, editado: assinado), isNull);
      expect(avisoAssinaturaDoPedido(original: assinado, editado: mudou),
          'O cliente precisa assinar o pedido de novo, porque os itens mudaram.');
      final semAss = _pedidoGuardado(assinado: false);
      expect(avisoAssinaturaDoPedido(original: semAss, editado: semAss),
          'O cliente precisa assinar o pedido.');
      final rascunho = {...assinado, 'so_local': 1};
      expect(avisoAssinaturaDoPedido(original: rascunho, editado: rascunho), isNull,
          reason: 'rascunho assinado e sem mudança');
      expect(avisoAssinaturaDoPedido(original: rascunho, editado: mudou),
          'O cliente precisa assinar o pedido de novo, porque os itens mudaram.');
      final rascunhoSemAss = {...semAss, 'so_local': 1};
      expect(avisoAssinaturaDoPedido(original: rascunhoSemAss, editado: rascunhoSemAss),
          'O cliente precisa assinar o pedido.');
    });

    test('mensagem: reenvio de pronto sem mudanca diz so "Pedido salvo."', () {
      expect(mensagemGravacao(ResultadoGravacao.enviado, 'pronto'), 'Pedido salvo.');
      expect(mensagemGravacao(ResultadoGravacao.enviado, 'salvo'), 'Pedido enviado para produção.');
      expect(mensagemGravacao(ResultadoGravacao.pendente, 'pronto'),
          'Pedido salvo. Será enviado quando houver internet.');
    });
  });

  group('pedido novo', () {
    testWidgets('Enviar pedido sem assinatura abre a tela de assinatura e nao grava',
        (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _preencherPedidoNovo(tester);
      await _abrirResumoETocar(tester, 'Enviar pedido');

      expect(espiao.pedidos, [(TipoAssinatura.pedido, 'O cliente precisa assinar o pedido.')]);
      expect(espiao.gravados, isEmpty, reason: 'desistiu da assinatura: nada gravado');
      expect(find.text('Fazer Pedido'), findsOneWidget, reason: 'o formulário continua');
      expect(find.text('Finalizar'), findsNothing);
    });

    testWidgets('Enviar pedido com a assinatura grava salvo, envia e leva a assinatura',
        (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _preencherPedidoNovo(tester);
      await _abrirResumoETocar(tester, 'Enviar pedido');

      expect(espiao.pedidos.single.$1, TipoAssinatura.pedido);
      final g = espiao.gravados.single;
      expect(g['status'], 'salvo');
      expect(g['so_local'], 0);
      expect(g['assinatura_pedido'], _png);
      expect(g.containsKey('assinatura'), isFalse, reason: 'a entrega é assinada depois');
      expect(find.text('Pedido enviado para produção.'), findsOneWidget);
      expect(find.text('Fazer Pedido'), findsNothing);
    });

    testWidgets('Salvar rascunho grava so no aparelho e nao pede assinatura', (tester) async {
      final espiao = _Espiao()..resultado = ResultadoGravacao.rascunho;
      await _abrir(
        tester,
        PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _preencherPedidoNovo(tester);
      await _abrirResumoETocar(tester, 'Salvar rascunho');

      expect(espiao.pedidos, isEmpty);
      final g = espiao.gravados.single;
      expect(g['status'], 'salvo');
      expect(g['so_local'], 1);
    });
  });

  group('assinatura colhida antes', () {
    testWidgets('pedido novo: assinou e depois mudou a quantidade, pede de novo', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _preencherPedidoNovo(tester);
      await _assinarNoResumoEFechar(tester);
      expect(espiao.pedidos, [(TipoAssinatura.pedido, null)]);

      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '5');
      await tester.pumpAndSettle();
      espiao.resposta = null; // o cliente não assina de novo
      await _abrirResumoETocar(tester, 'Enviar pedido');

      expect(espiao.pedidos.last, (TipoAssinatura.pedido, kAvisoAssinarPedidoDeNovo));
      expect(espiao.gravados, isEmpty, reason: 'a assinatura antiga não cobre os itens novos');

      espiao.resposta = _png;
      await _abrirResumoETocar(tester, 'Enviar pedido');
      expect(espiao.pedidos.length, 3);
      final g = espiao.gravados.single;
      expect((g['produtos'] as List).first['quantidade'], 5);
      expect(g['assinatura_pedido'], _png);
    });

    testWidgets('pedido novo: assinou e nao mudou nada, nao pede de novo', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _preencherPedidoNovo(tester);
      await _assinarNoResumoEFechar(tester);
      await _abrirResumoETocar(tester, 'Enviar pedido');
      expect(espiao.pedidos.length, 1);
      expect(espiao.gravados.single['assinatura_pedido'], _png);
    });

    testWidgets('edicao: assinou e depois mudou a quantidade, pede de novo', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _assinarNoResumoEFechar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '4');
      await tester.pumpAndSettle();
      espiao.resposta = null;
      await _abrirResumoETocar(tester, 'Salvar alterações');

      expect(espiao.pedidos, [
        (TipoAssinatura.pedido, null),
        (TipoAssinatura.pedido, kAvisoAssinarPedidoDeNovo),
      ]);
      expect(espiao.gravados, isEmpty);
      expect(find.text('Editar Pedido'), findsOneWidget);
    });

    testWidgets('edicao: assinou e depois mudou o cliente, pede de novo', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _assinarNoResumoEFechar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Padaria Nova');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Salvar alterações');

      expect(espiao.pedidos.last, (TipoAssinatura.pedido, kAvisoAssinarPedidoDeNovo));
      final g = espiao.gravados.single;
      expect(g['cliente_nome'], 'Padaria Nova');
      expect(g['assinatura_pedido'], _png);
      expect(g['status'], 'salvo');
    });

    testWidgets('edicao: assinou e nao mudou nada, leva a assinatura nova sem pedir',
        (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(assinado: false, status: 'salvo'),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _assinarNoResumoEFechar(tester);
      await _abrirResumoETocar(tester, 'Salvar alterações');
      expect(espiao.pedidos.length, 1);
      expect(espiao.gravados.single['assinatura_pedido'], _png);
    });
  });

  group('rascunho', () {
    /// A linha como o SQLite guarda o que a tela gravou (itens em texto JSON,
    /// assinatura do pedido em hex "0x...").
    Map<String, dynamic> comoNoAparelho(Map<String, dynamic> g) => {
          ...g,
          'id': 1000000001,
          'produtos': jsonEncode(g['produtos']),
          if (g['assinatura_pedido'] is Uint8List)
            'assinatura_pedido': '0x${cvt.hex.encode(g['assinatura_pedido'] as Uint8List)}',
          'pendente_envio': 0,
        }..remove(kLimparAssinaturaPedido);

    PedidoPage pedidoNovo(_Espiao espiao) => PedidoPage(
          vendedor: _vendedor,
          dadosParaCaptura: (
            clientes: const [
              {'id': 7, 'nome': 'Padaria Central'}
            ],
            produtos: _catalogo
          ),
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        );

    Map<String, dynamic> rascunhoGuardado({bool assinado = true}) =>
        {..._pedidoGuardado(status: 'salvo', assinado: assinado), 'so_local': 1};

    testWidgets('assinou, Salvar rascunho guarda a assinatura; reabrir e Salvar alteracoes '
        'envia sem pedir de novo', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(tester, pedidoNovo(espiao));
      await _preencherPedidoNovo(tester);
      await _assinarNoResumoEFechar(tester);
      espiao.resultado = ResultadoGravacao.rascunho;
      await _abrirResumoETocar(tester, 'Salvar rascunho');

      final rascunho = espiao.gravados.single;
      expect(rascunho['so_local'], 1);
      expect(rascunho['assinatura_pedido'], _png, reason: 'a assinatura cobre a tela');
      expect(rascunho.containsKey(kLimparAssinaturaPedido), isFalse);

      // Reabre o rascunho e salva as alterações sem mexer em nada.
      espiao.resultado = ResultadoGravacao.enviado;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: comoNoAparelho(rascunho),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _abrirResumoETocar(tester, 'Salvar alterações');

      expect(espiao.pedidos, [(TipoAssinatura.pedido, null)],
          reason: 'só a assinatura colhida antes do rascunho');
      final enviado = espiao.gravados.last;
      expect(espiao.gravados.length, 2);
      expect(enviado['so_local'], 0, reason: 'Salvar alterações envia');
      expect(enviado['assinatura_pedido'], '0x${cvt.hex.encode(_png)}');
    });

    testWidgets('assinou e mudou a quantidade: Salvar rascunho nao guarda a assinatura',
        (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(tester, pedidoNovo(espiao));
      await _preencherPedidoNovo(tester);
      await _assinarNoResumoEFechar(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '5');
      await tester.pumpAndSettle();
      espiao.resultado = ResultadoGravacao.rascunho;
      await _abrirResumoETocar(tester, 'Salvar rascunho');

      final g = espiao.gravados.single;
      expect(g['so_local'], 1);
      expect(g.containsKey('assinatura_pedido'), isFalse);
      expect(g[kLimparAssinaturaPedido], isTrue);
      expect(espiao.pedidos.length, 1, reason: 'rascunho não pede assinatura');
    });

    testWidgets('rascunho sem assinatura: Salvar alteracoes pede', (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: rascunhoGuardado(assinado: false),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _abrirResumoETocar(tester, 'Salvar alterações');
      expect(espiao.pedidos, [(TipoAssinatura.pedido, kAvisoAssinarPedido)]);
      expect(espiao.gravados, isEmpty);
    });

    testWidgets('rascunho assinado e editado depois: Salvar alteracoes pede de novo',
        (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: rascunhoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '4');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Salvar alterações');
      expect(espiao.pedidos, [(TipoAssinatura.pedido, kAvisoAssinarPedidoDeNovo)]);
      expect(espiao.gravados, isEmpty);
    });

    testWidgets('Salvar rascunho no rascunho aberto fica no aparelho, sem pedir assinatura',
        (tester) async {
      final espiao = _Espiao()..resultado = ResultadoGravacao.rascunho;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: rascunhoGuardado(assinado: false),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '4');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Salvar rascunho');

      expect(espiao.pedidos, isEmpty);
      final g = espiao.gravados.single;
      expect(g['so_local'], 1, reason: 'continua rascunho, não envia');
      expect(g['status'], 'salvo');
      expect(find.text('Editar Pedido'), findsNothing, reason: 'gravou e fechou');
    });

    testWidgets('Salvar rascunho: assinatura guardada fica se nada mudou e sai se mudou',
        (tester) async {
      final espiao = _Espiao()..resultado = ResultadoGravacao.rascunho;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: rascunhoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _abrirResumoETocar(tester, 'Salvar rascunho');
      expect(espiao.gravados.single['assinatura_pedido'], _hex0x);
      expect(espiao.gravados.single.containsKey(kLimparAssinaturaPedido), isFalse);

      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: rascunhoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '4');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Salvar rascunho');
      final g = espiao.gravados.last;
      expect(g['assinatura_pedido'], isNull);
      expect(g[kLimparAssinaturaPedido], isTrue);
      expect(espiao.pedidos, isEmpty);
    });

    testWidgets('pedido ja enviado nao oferece Salvar rascunho', (tester) async {
      await _abrir(
        tester,
        PedidoPageEdit(pedido: _pedidoGuardado(status: 'salvo'), produtosParaCaptura: _catalogo),
      );
      await tester
          .tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();
      expect(find.text('Salvar alterações'), findsOneWidget);
      expect(find.text('Salvar rascunho'), findsNothing);
    });
  });

  group('salvar alteracoes', () {
    testWidgets('Salvar alteracoes com itens mudados exige nova assinatura', (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '4');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Salvar alterações');

      expect(espiao.pedidos, [
        (
          TipoAssinatura.pedido,
          'O cliente precisa assinar o pedido de novo, porque os itens mudaram.'
        )
      ]);
      expect(espiao.gravados, isEmpty, reason: 'sem a nova assinatura nada é gravado');
      expect(find.text('Editar Pedido'), findsOneWidget);

      // Agora o cliente assina.
      espiao.resposta = _png;
      await _abrirResumoETocar(tester, 'Salvar alterações');
      expect(espiao.pedidos.length, 2);
      final g = espiao.gravados.single;
      expect(g['assinatura_pedido'], _png);
      expect(g['status'], 'salvo', reason: 'mudou itens: volta para em aberto');
      final itens = (g['produtos'] as List).cast<Map>();
      final leite = itens.firstWhere((i) => i['nome'] == 'Leite ninho');
      expect(leite['quantidade'], 4);
      expect(leite['preco'], 10.9, reason: 'o preço combinado no pedido fica');
      expect(itens.any((i) => i['nome'] == 'Doce antigo'), isTrue,
          reason: 'produto que saiu do catálogo não some do pedido');
      expect(find.text('Pedido enviado para produção.'), findsOneWidget);
    });

    testWidgets('Salvar alteracoes sem mudar itens nao pede assinatura', (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _abrirResumoETocar(tester, 'Salvar alterações');

      expect(espiao.pedidos, isEmpty);
      final g = espiao.gravados.single;
      expect(g['produtos'], _itensGuardados, reason: 'nem o preço novo do catálogo muda o pedido');
      expect(g['status'], 'pronto');
      expect(g['cliente_nome'], 'Padaria Central ', reason: 'o servidor compara o valor cru');
      expect(g['assinatura_pedido'], _hex0x, reason: 'a assinatura guardada fica');
      expect(find.text('Pedido salvo.'), findsOneWidget);
      expect(find.text('Pedido enviado para produção.'), findsNothing);
    });
  });

  group('entrega', () {
    testWidgets('Registrar entrega so pede a assinatura da entrega', (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPageEdit(
          // sem assinatura do pedido e com o item mudado: mesmo assim a
          // entrega só pede a assinatura da entrega
          pedido: _pedidoGuardado(status: 'salvo', assinado: false),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
          gravarArquivoAssinatura: (b, {required numero}) async => '/sig/entrega_$numero.png',
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Qtd').first, '5');
      await tester.pumpAndSettle();
      await _abrirResumoETocar(tester, 'Registrar entrega');

      expect(espiao.pedidos, [(TipoAssinatura.entrega, null)]);
      final g = espiao.gravados.single;
      expect(g['status'], 'finalizado');
      expect(g['assinatura'], _png);
      expect(g['assinatura_path'], '/sig/entrega_70.png');
      expect(g.containsKey('assinatura_pedido'), isFalse);
    });

    testWidgets('arquivo da entrega falhou: vai sem caminho, nunca o arquivo antigo',
        (tester) async {
      final espiao = _Espiao()..resposta = _png;
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: {..._pedidoGuardado(), 'assinatura_path': '/sig/entrega_antiga.png'},
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
          gravarArquivoAssinatura: (b, {required numero}) async =>
              throw const FileSystemException('disco cheio'),
        ),
      );
      await _abrirResumoETocar(tester, 'Registrar entrega');
      final g = espiao.gravados.single;
      expect(g['status'], 'finalizado');
      expect(g['assinatura'], _png);
      expect(g['assinatura_path'], isNull);
    });

    testWidgets('Registrar entrega sem assinar nao grava', (tester) async {
      final espiao = _Espiao();
      await _abrir(
        tester,
        PedidoPageEdit(
          pedido: _pedidoGuardado(),
          produtosParaCaptura: _catalogo,
          pedirAssinatura: espiao.pedir,
          gravar: espiao.gravar,
        ),
      );
      await _abrirResumoETocar(tester, 'Registrar entrega');
      expect(espiao.pedidos.single.$1, TipoAssinatura.entrega);
      expect(espiao.gravados, isEmpty);
      expect(find.text('Editar Pedido'), findsOneWidget);
    });
  });

  group('meus pedidos', () {
    testWidgets('pronto fica em Em aberto com o selo Pronto e pode ser editado', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildMilkdimTheme(),
        home: PedidosPage(vendedorCodigo: '0003', pedidosParaCaptura: [
          {..._pedidoGuardado(), 'cliente_nome': 'Padaria Central'},
          {
            ..._pedidoGuardado(status: 'finalizado'),
            'id': 43,
            'numero': '71',
            'cliente_nome': 'Mercearia Boa Vista',
          },
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Em aberto (1)'), findsOneWidget);
      expect(find.text('Entregues (1)'), findsOneWidget);
      expect(find.textContaining('Finalizados'), findsNothing);
      expect(find.text('Pronto'), findsOneWidget);
      expect(find.text('Padaria Central'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Cancelar pedido'), findsOneWidget);
    });

    testWidgets('selos seguem os nomes das abas: Em aberto e Entregue', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildMilkdimTheme(),
        home: PedidosPage(vendedorCodigo: '0003', pedidosParaCaptura: [
          {..._pedidoGuardado(status: 'salvo'), 'cliente_nome': 'Padaria Central'},
          {
            ..._pedidoGuardado(status: 'finalizado'),
            'id': 43,
            'numero': '71',
            'cliente_nome': 'Mercearia Boa Vista',
          },
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Em aberto'), findsOneWidget, reason: 'selo do pedido salvo');
      expect(find.text('Salvo'), findsNothing);

      await tester.tap(find.text('Entregues (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Entregue'), findsOneWidget);
      expect(find.text('Finalizado'), findsNothing);
    });
  });

  group('pdf', () {
    test('pdf com uma assinatura so mostra o rotulo dela', () {
      expect(assinaturasDoPdf(pedido: _png, entrega: null).map((a) => a.rotulo),
          ['Assinatura do pedido']);
      expect(assinaturasDoPdf(pedido: null, entrega: _png).map((a) => a.rotulo),
          ['Assinatura da entrega']);
      final duas = assinaturasDoPdf(pedido: _png, entrega: _png);
      expect(duas.map((a) => a.rotulo), ['Assinatura do pedido', 'Assinatura da entrega']);
      expect(duas.every((a) => a.imagem == _png), isTrue);
    });

    test('pdf cai para os bytes quando o caminho da assinatura esta vazio', () {
      final p = {'assinatura_pedido': _hex0x, 'assinatura_pedido_path': null};
      expect(
          imagemDaAssinatura(p,
              chaveBytes: 'assinatura_pedido', chaveCaminho: 'assinatura_pedido_path'),
          _png);
      final comCaminhoVelho = {
        'assinatura_pedido': _hex0x,
        'assinatura_pedido_path': '/nao/existe.png'
      };
      expect(
          imagemDaAssinatura(comCaminhoVelho,
              chaveBytes: 'assinatura_pedido', chaveCaminho: 'assinatura_pedido_path'),
          _png);
      expect(
          imagemDaAssinatura(const {}, chaveBytes: 'assinatura', chaveCaminho: 'assinatura_path'),
          isNull);
    });
  });
}
