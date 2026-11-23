// Captura das telas do app do vendedor em build/visual/ (revisão humana, sem golden).
// Só telas que dá para montar sem rede nem SQLite; os dados são falsos.
// Roda com o resto dos testes; só ela: flutter test --tags visual
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:milkdim_ui/testing/md_visual.dart';

import 'package:milkdim_app/pages/assinatura_page.dart';
import 'package:milkdim_app/pages/configuracoes_page.dart';
import 'package:milkdim_app/pages/home_page.dart';
import 'package:milkdim_app/pages/login_page.dart';
import 'package:milkdim_app/pages/novo_cliente_page.dart';
import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:milkdim_app/pages/pedido_page.dart';
import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/produto.dart';
import 'package:milkdim_app/widgets/pedido_ui.dart';

const _vendedor = <String, dynamic>{'codigo': '0001', 'nome': 'João Silva', 'ativo': 1};

const _produtos = <Produto>[
  Produto(id: 1, nome: 'Queijo Minas Frescal 500 g', preco: 18.9),
  Produto(id: 2, nome: 'Requeijão Cremoso 200 g', preco: 7.5),
  Produto(id: 3, nome: 'Manteiga com Sal 200 g', preco: 12.4),
  Produto(id: 4, nome: 'Iogurte Natural Integral 170 g', preco: 3.2),
  Produto(id: 5, nome: 'Doce de Leite Pastoso 400 g', preco: 14.0),
];

final _pedidos = <Map<String, dynamic>>[
  {
    'id': 1,
    'numero': '128',
    'status': 'finalizado',
    'pendente_envio': 1,
    'datahora': '2026-11-19T13:40:00Z',
    'total': 245.6,
    'cliente_nome': 'Padaria Central',
    'cliente_cidade': 'Uberlândia',
    'cliente_telefone': '(34) 99999-1234',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos':
        '[{"nome":"Queijo Minas Frescal 500 g","quantidade":8},{"nome":"Requeijão Cremoso 200 g","quantidade":12}]',
  },
  {
    'id': 2,
    'numero': '127',
    'status': 'finalizado',
    'pendente_envio': 0,
    'datahora': '2026-11-18T10:05:00Z',
    'total': 98.0,
    'cliente_nome': 'Mercearia Boa Vista Ltda.',
    'cliente_cidade': 'Araguari',
    'cliente_cpf_cnpj': '12.345.678/0001-90',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos':
        '[{"nome":"Manteiga com Sal 200 g","quantidade":4},{"nome":"Iogurte Natural Integral 170 g","quantidade":10},{"nome":"Doce de Leite Pastoso 400 g","quantidade":1},{"nome":"Requeijão Cremoso 200 g","quantidade":2}]',
  },
  {
    'id': 3,
    'numero': '129',
    'status': 'salvo',
    'pendente_envio': 0,
    'datahora': '2026-11-19T15:00:00Z',
    'total': 37.8,
    'cliente_nome': 'Lanchonete do Zé',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos': '[{"nome":"Queijo Minas Frescal 500 g","quantidade":2}]',
  },
];

final _cancelados = <Map<String, dynamic>>[
  {
    'id': 4,
    'numero': '126',
    'status': 'cancelado',
    'pendente_envio': 0,
    'datahora': '2026-11-17T09:20:00Z',
    'total': 64.5,
    'cliente_nome': 'Mercadinho Primavera',
    'cliente_cidade': 'Uberlândia',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos': '[{"nome":"Requeijão Cremoso 200 g","quantidade":5}]',
  },
];

final _naoEnviados = <Map<String, dynamic>>[
  {
    'id': 1000000011,
    'numero': '130',
    'status': 'salvo',
    'so_local': 1,
    'pendente_envio': 0,
    'datahora': '2026-11-20T11:00:00Z',
    'total': 37.8,
    'cliente_nome': 'Lanchonete do Zé',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos': '[{"nome":"Queijo Minas Frescal 500 g","quantidade":2}]',
  },
  {
    'id': 1000000012,
    'numero': '131',
    'status': 'salvo',
    'erro_envio': 'numero',
    'pendente_envio': 1,
    'datahora': '2026-11-20T12:00:00Z',
    'total': 22.5,
    'cliente_nome': 'Padaria Central',
    'vendedor_nome': 'João Silva',
    'vendedor_codigo': '0001',
    'produtos': '[{"nome":"Requeijão Cremoso 200 g","quantidade":3}]',
  },
];

void main() {
  setUpAll(carregarFontesReais);

  testWidgets('login', (tester) async {
    await capturar(tester, const LoginPage(), 'app_login');
  });

  testWidgets('início com pendentes', (tester) async {
    await capturar(
      tester,
      const HomePage(vendedor: _vendedor, pendentesParaCaptura: 2),
      'app_inicio',
    );
  });

  testWidgets('início sem pendentes', (tester) async {
    await capturar(
      tester,
      const HomePage(vendedor: _vendedor, pendentesParaCaptura: 0),
      'app_inicio_sem_pendentes',
    );
  });

  testWidgets('meus pedidos', (tester) async {
    await capturar(
      tester,
      PedidosPage(vendedorCodigo: '0001', pedidosParaCaptura: _pedidos),
      'app_pedidos',
    );
  });

  testWidgets('meus pedidos cancelados', (tester) async {
    await capturar(
      tester,
      PedidosPage(
        vendedorCodigo: '0001',
        pedidosParaCaptura: [..._pedidos, ..._cancelados],
        abaInicialParaCaptura: 2,
      ),
      'meus_pedidos_cancelados',
    );
  });

  testWidgets('pedido não enviado', (tester) async {
    await capturar(
      tester,
      PedidosPage(vendedorCodigo: '0001', pedidosParaCaptura: _naoEnviados),
      'pedido_nao_enviado',
    );
  });

  testWidgets('meus pedidos vazio', (tester) async {
    await capturar(
      tester,
      const PedidosPage(vendedorCodigo: '0001', pedidosParaCaptura: []),
      'app_pedidos_vazio',
    );
  });

  testWidgets('fazer pedido', (tester) async {
    await capturar(
      tester,
      const PedidoPage(
        vendedor: _vendedor,
        dadosParaCaptura: (
          clientes: [
            {'id': 1, 'nome': 'Padaria Central'},
          ],
          produtos: _produtos,
        ),
      ),
      'app_pedido',
      tamanho: const Size(412, 1900),
    );
  });

  testWidgets('editar pedido', (tester) async {
    await capturar(
      tester,
      PedidoPageEdit(pedido: _pedidos[2], produtosParaCaptura: _produtos),
      'app_pedido_editar',
      tamanho: const Size(412, 1900),
    );
  });

  testWidgets('resumo do pedido', (tester) async {
    await capturar(
      tester,
      Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MdSpace.xl),
            child: ResumoPedido(
              numero: '129',
              cliente: 'Lanchonete do Zé',
              ultimoPedido: DateTime.now().subtract(const Duration(days: 20)),
              campos: const [
                ('Nome Fantasia', ''),
                ('Telefone', '(34) 99999-1234'),
                ('Cidade', 'Uberlândia'),
                ('CPF/CNPJ', ''),
              ],
              vendedor: 'João Silva',
              itens: const [
                (nome: 'Queijo Minas Frescal 500 g', quantidade: 2, subtotal: 37.8),
                (nome: 'Requeijão Cremoso 200 g', quantidade: 3, subtotal: 22.5),
              ],
              total: 60.3,
              assinatura: null,
              ocupado: false,
              onAssinar: () {},
              onSalvar: () {},
              onFinalizar: () {},
            ),
          ),
        ),
      ),
      'app_pedido_resumo',
    );
  });

  testWidgets('assinatura', (tester) async {
    await capturar(tester, const AssinaturaPage(), 'app_assinatura');
  });

  testWidgets('configurações', (tester) async {
    await capturar(tester, const ConfiguracoesPage(), 'app_configuracoes');
  });

  testWidgets('novo cliente', (tester) async {
    await capturar(tester, const NovoClientePage(), 'app_novo_cliente');
  });
}
