// test/telas_comprovante_test.dart
//
// Fase A.2 nas telas do vendedor: enviar o pedido com a assinatura do pedido,
// salvar alterações (nova assinatura só quando mudam itens ou cliente),
// registrar a entrega com a assinatura da entrega, o selo "Pronto" em Meus
// pedidos e o PDF com as duas assinaturas. Dados falsos.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';
import 'package:milkdim_app/utils/produto.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';
import 'package:milkdim_app/widgets/pedido_ui.dart';

/// PNG 1x1 de verdade (a tela mostra a assinatura com Image.memory).
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
final String _hex0x = '0x${cvt.hex.encode(_png)}';

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

/// Abre o resumo e toca [botao] e avança só o bastante para a pergunta do
/// comprovante aparecer (sem `pumpAndSettle`: a tela pode seguir ocupada).
Future<void> _abrirResumoETocar(WidgetTester tester, String botao) async {
  await tester
      .tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(botao));
  await tester.pumpAndSettle();
  await tester.tap(find.text(botao));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  Widget tela(_Espiao e, List<Map<String, dynamic>> enviados,
          {String status = 'salvo', Future<void> Function(Map<String, dynamic>)? envio,
          Future<Map<String, dynamic>?> Function(int)? ler}) =>
      PedidoPageEdit(
        pedido: _pedidoGuardado(status: status, assinado: false),
        produtosParaCaptura: _catalogo,
        pedirAssinatura: e.pedir,
        gravar: e.gravar,
        gravarArquivoAssinatura: (b, {required numero}) async => '/sig/entrega_$numero.png',
        enviarComprovante: envio ??
            (p) async {
              enviados.add(p);
            },
        lerPedidoGravado: ler ?? (id) async => {'id': id, 'numero': '70', 'relido': true},
      );

  const pergunta = 'Entrega registrada. Enviar comprovante ao cliente?';

  testWidgets('Enviar comprovante: manda o pedido relido e fecha com a situacao', (tester) async {
    final e = _Espiao()..resposta = _png;
    final enviados = <Map<String, dynamic>>[];
    await _abrir(tester, tela(e, enviados));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    expect(find.text(pergunta), findsOneWidget);
    expect(find.text('Editar Pedido'), findsOneWidget, reason: 'ainda aberta');
    await tester.tap(find.text('Enviar comprovante'));
    await tester.pumpAndSettle();
    expect(enviados.single['relido'], isTrue);
    expect(enviados.single['id'], 42);
    expect(find.text('Editar Pedido'), findsNothing);
  });

  testWidgets('sem poder rereler: usa o que acabou de gravar', (tester) async {
    final e = _Espiao()..resposta = _png;
    final enviados = <Map<String, dynamic>>[];
    await _abrir(tester, tela(e, enviados, ler: (id) async => throw Exception('x')));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    await tester.tap(find.text('Enviar comprovante'));
    await tester.pumpAndSettle();
    expect(enviados.single['status'], 'finalizado');
    expect(enviados.single.containsKey('relido'), isFalse);
  });

  testWidgets('Agora nao: fecha sem enviar; tocar fora nao fecha a pergunta', (tester) async {
    final e = _Espiao()..resposta = _png;
    final enviados = <Map<String, dynamic>>[];
    await _abrir(tester, tela(e, enviados));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(pergunta), findsOneWidget);
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    expect(enviados, isEmpty);
    expect(find.text('Editar Pedido'), findsNothing);
  });

  testWidgets('falha ao enviar: avisa e fecha assim mesmo', (tester) async {
    final e = _Espiao()..resposta = _png;
    await _abrir(tester, tela(e, [], envio: (p) async => throw Exception('pdf')));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    await tester.tap(find.text('Enviar comprovante'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Não foi possível gerar o comprovante.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Editar Pedido'), findsNothing);
  });

  testWidgets('entrega so no aparelho (pendente): a pergunta aparece', (tester) async {
    final e = _Espiao()
      ..resposta = _png
      ..resultado = ResultadoGravacao.pendente;
    await _abrir(tester, tela(e, []));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    expect(find.text(pergunta), findsOneWidget);
  });

  testWidgets('Salvar nao mostra a pergunta', (tester) async {
    final e = _Espiao()..resposta = _png;
    await _abrir(tester, tela(e, []));
    await _abrirResumoETocar(tester, 'Salvar alterações');
    expect(e.gravados, isNotEmpty);
    expect(find.text(pergunta), findsNothing);
    expect(find.text('Editar Pedido'), findsNothing);
  });

  testWidgets('enquanto o comprovante e gerado a tela fica travada', (tester) async {
    final e = _Espiao()..resposta = _png;
    final preso = Completer<void>();
    await _abrir(tester, tela(e, [], envio: (p) => preso.future));
    await _abrirResumoETocar(tester, 'Registrar entrega');
    await tester.tap(find.text('Enviar comprovante'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final antes = e.gravados.length;
    final botao = find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton));
    await tester.tap(botao, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Registrar entrega'), findsNothing, reason: 'resumo nao abriu');
    expect(e.gravados.length, antes);
    preso.complete();
    await tester.pumpAndSettle();
    expect(find.text('Editar Pedido'), findsNothing);
  });
}
