// Detalhe do pedido: a quantidade de cada item tem que aparecer na tela, mesmo com
// nomes de produto longos (antes a tabela rolava de lado e escondia Qtd/Subtotal).
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/widgets/detalhe_pedido.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:milkdim_ui/testing/md_visual.dart';

const _itens = [
  PedidoItem(nome: '1100g Chocolate Branco Com Calda de Frutas Vermelhas', preco: 89, quantidade: 3),
  PedidoItem(nome: '1100g Chocolate com Granelle', preco: 85, quantidade: 2),
  PedidoItem(nome: '1100g Pudim Tradicional (leite condensado) 1100g (Revenda)', preco: 56, quantidade: 5),
  PedidoItem(nome: '550g pudim Tradicional', preco: 32, quantidade: 1),
];

final _pedido = Pedido(
  id: 7,
  numero: '42',
  status: 'salvo',
  total: 89.0 * 3 + 85 * 2 + 56 * 5 + 32,
  vendedorNome: 'Vendedor Teste',
  clienteNome: 'Cliente Teste',
  itens: _itens,
);

Future<DetalheDoPedido> _buscar(int id) async =>
    (raw: <String, dynamic>{'id': id, 'numero': '42'}, parsed: _pedido);

/// Abre o detalhe assim que monta (para a captura sair com a folha aberta).
class _AbreDetalhe extends StatefulWidget {
  const _AbreDetalhe();
  @override
  State<_AbreDetalhe> createState() => _AbreDetalheState();
}

class _AbreDetalheState extends State<_AbreDetalhe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => abrirDetalhesPedido(context, _pedido, buscar: _buscar),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

void main() {
  setUpAll(carregarFontesReais);

  testWidgets('itens mostram quantidade e subtotal dentro da tela do celular', (tester) async {
    await capturar(tester, const _AbreDetalhe(), 'detalhe_itens_celular');
    await tester.pumpAndSettle();

    final largura = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final t in ['3×', '2×', '5×', '1×', '3 unidades × R\$ 89,00', '1 unidade × R\$ 32,00', 'R\$ 280,00']) {
      final f = find.text(t);
      expect(f, findsOneWidget, reason: t);
      final r = tester.getRect(f);
      expect(r.right <= largura && r.left >= 0, isTrue, reason: '$t fora da tela: $r');
    }
  });

  testWidgets('captura no computador', (tester) async {
    await capturar(tester, const _AbreDetalhe(), 'detalhe_itens_windows', tamanho: const Size(1280, 800));
    await tester.pumpAndSettle();
    expect(find.text('5×'), findsOneWidget);
  });
}
