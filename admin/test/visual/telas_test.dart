// Capturas das telas do Controle com dados falsos (sem Supabase).
// Gera PNGs em build/visual/ só para revisão; não compara com golden.
//   flutter test --tags visual
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/cliente.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/models/produto.dart';
import 'package:milkdim_admin/models/vendedor.dart';
import 'package:milkdim_admin/pages/home_page.dart';
import 'package:milkdim_admin/pages/login_page.dart';
import 'package:milkdim_admin/tabs/clientes_tab.dart';
import 'package:milkdim_admin/tabs/pedidos_tab.dart';
import 'package:milkdim_admin/tabs/producao_tab.dart';
import 'package:milkdim_admin/tabs/produtos_tab.dart';
import 'package:milkdim_admin/tabs/vendedores_tab.dart';
import 'package:milkdim_admin/widgets/detalhe_pedido.dart';
import 'package:milkdim_ui/testing/md_visual.dart';

const _windows = Size(1366, 800);
const _windowsPequeno = Size(1024, 720);
const _celular = Size(412, 892);

// ---------------------------- dados falsos ----------------------------

Future<List<Vendedor>> _vendedores() async => [
      const Vendedor(
          id: 1, codigo: '0001', nome: 'João Pereira', ativo: true,
          anotacao: 'Rota centro, segunda e quarta'),
      const Vendedor(id: 2, codigo: '0002', nome: 'Maria Aparecida Santos', ativo: true),
      const Vendedor(
          id: 3, codigo: '0003', nome: 'Carlos Henrique Oliveira', ativo: false,
          anotacao: 'Afastado até dezembro'),
      const Vendedor(id: 4, codigo: '0004', nome: 'Ana Beatriz Lima', ativo: true),
      const Vendedor(
          id: 5, codigo: '0005', nome: 'Rafael Souza', ativo: true,
          anotacao: 'Atende padarias da zona norte'),
      const Vendedor(id: 6, codigo: '0006', nome: 'Fernanda Costa', ativo: true),
    ];

Future<List<Produto>> _produtos() async => [
      const Produto(id: 1, codigo: '1001', nome: 'Leite integral 1L', unidade: 'CX', preco: 64.90, ativo: true),
      const Produto(id: 2, codigo: '1002', nome: 'Queijo mussarela peça', unidade: 'KG', preco: 38.50, ativo: true),
      const Produto(id: 3, codigo: '1003', nome: 'Iogurte natural 170 g', unidade: 'UN', preco: 3.29, ativo: true),
      const Produto(id: 4, codigo: '1004', nome: 'Manteiga com sal 200 g', unidade: 'UN', preco: 11.90, ativo: true),
      const Produto(id: 5, codigo: '1005', nome: 'Requeijão cremoso 200 g', unidade: 'UN', preco: 7.45, ativo: false),
      const Produto(id: 6, codigo: '1006', nome: 'Doce de leite pastoso 400 g', unidade: 'UN', preco: 12.80, ativo: true),
      const Produto(id: 7, nome: 'Bebida láctea morango 1L', unidade: 'UN', preco: 6.20, ativo: true),
      const Produto(id: 8, codigo: '1008', nome: 'Creme de leite 200 g', unidade: 'CX', preco: 89.00, ativo: true),
    ];

String _haDias(int dias, [int horas = 0]) =>
    DateTime.now().subtract(Duration(days: dias, hours: horas)).toUtc().toIso8601String();

Future<List<Pedido>> _pedidos() async => [
      Pedido(
        id: 1042, numero: '318', status: 'finalizado', datahora: _haDias(0, 2),
        vendedorCodigo: '0001', vendedorNome: 'João Pereira',
        clienteNome: 'Padaria Pão Quente', clienteCidade: 'Uberlândia',
        clienteTelefone: '(34) 3214-5566', clienteCpfCnpj: '12.345.678/0001-90',
        itens: const [
          PedidoItem(nome: 'Leite integral 1L', preco: 64.90, quantidade: 4),
          PedidoItem(nome: 'Queijo mussarela peça', preco: 38.50, quantidade: 6),
          PedidoItem(nome: 'Manteiga com sal 200 g', preco: 11.90, quantidade: 12),
          PedidoItem(nome: 'Iogurte natural 170 g', preco: 3.29, quantidade: 24),
        ],
        total: 712.36,
      ),
      Pedido(
        id: 1041, numero: '317', status: 'salvo', datahora: _haDias(0, 5),
        vendedorCodigo: '0002', vendedorNome: 'Maria Aparecida Santos',
        clienteNome: 'Mercado Bom Preço', clienteCidade: 'Araguari',
        clienteWhatsapp: '(34) 99876-1122',
        itens: const [
          PedidoItem(nome: 'Requeijão cremoso 200 g', preco: 7.45, quantidade: 20),
          PedidoItem(nome: 'Doce de leite pastoso 400 g', preco: 12.80, quantidade: 10),
        ],
        total: 277.00,
      ),
      Pedido(
        id: 1040, numero: '316', status: 'pendente', datahora: _haDias(1, 3),
        vendedorCodigo: '0005', vendedorNome: 'Rafael Souza',
        clienteNome: 'Lanchonete da Praça', clienteCidade: 'Uberlândia',
        clienteTelefone: '(34) 3222-0101', clienteEmail: 'contato@lanchonetedapraca.com.br',
        itens: const [
          PedidoItem(nome: 'Creme de leite 200 g', preco: 89.00, quantidade: 1),
        ],
        total: 89.00,
      ),
      Pedido(
        id: 1039, numero: '315', status: 'cancelado', datahora: _haDias(3),
        vendedorCodigo: '0001', vendedorNome: 'João Pereira',
        clienteNome: 'Supermercado Irmãos Ferreira Ltda', clienteCidade: 'Monte Alegre de Minas',
        clienteCpfCnpj: '98.765.432/0001-10',
        itens: const [
          PedidoItem(nome: 'Leite integral 1L', preco: 64.90, quantidade: 10),
          PedidoItem(nome: 'Bebida láctea morango 1L', preco: 6.20, quantidade: 30),
          PedidoItem(nome: 'Iogurte natural 170 g', preco: 3.29, quantidade: 48),
          PedidoItem(nome: 'Manteiga com sal 200 g', preco: 11.90, quantidade: 12),
          PedidoItem(nome: 'Queijo mussarela peça', preco: 38.50, quantidade: 4),
        ],
        total: 1309.72,
      ),
      Pedido(
        id: 1038, status: 'finalizado', datahora: _haDias(6),
        vendedorCodigo: '0004',
        clienteNome: 'Empório Sabor de Minas',
        itens: const [
          PedidoItem(nome: 'Doce de leite pastoso 400 g', preco: 12.80, quantidade: 6),
        ],
        total: 76.80,
      ),
    ];

Future<List<Cliente>> _clientes() async => [
      Cliente(
        id: 1, nome: 'Padaria Pão Quente', nomeFantasia: 'Pão Quente',
        telefone: '(34) 3214-5566', whatsapp: '(34) 99123-4567',
        email: 'compras@paoquente.com.br', cidade: 'Uberlândia',
        cpfCnpj: '12.345.678/0001-90', ativo: true, ultimoPedido: _haDias(2),
      ),
      Cliente(
        id: 2, nome: 'Mercado Bom Preço', telefone: '(34) 3241-0099',
        cidade: 'Araguari', cpfCnpj: '23.456.789/0001-01', ativo: true,
        ultimoPedido: _haDias(21),
      ),
      Cliente(
        id: 3, nome: 'Lanchonete da Praça', nomeFantasia: 'Da Praça',
        whatsapp: '(34) 99876-1122', cidade: 'Uberlândia', cpfCnpj: '345.678.901-23',
        ativo: true, ultimoPedido: _haDias(40),
      ),
      const Cliente(
        id: 4, nome: 'Supermercado Irmãos Ferreira Ltda', nomeFantasia: 'Ferreira',
        email: 'financeiro@irmaosferreira.com.br', cidade: 'Monte Alegre de Minas',
        cpfCnpj: '98.765.432/0001-10', ativo: false,
      ),
      Cliente(
        id: 5, nome: 'Empório Sabor de Minas', telefone: '(34) 3255-7788',
        cidade: 'Uberlândia', cpfCnpj: '45.678.901/0001-34', ativo: true,
        ultimoPedido: _haDias(0),
      ),
    ];

Future<List<Pedido>> _emAberto() async {
  final agora = DateTime.now();
  return [
    Pedido(
      id: 1041, numero: '317', status: 'salvo',
      vendedorCodigo: '0002', vendedorNome: 'Maria Aparecida Santos',
      clienteNome: 'Mercado Bom Preço',
      enviadoEm: agora.subtract(const Duration(hours: 5)),
      itens: const [
        PedidoItem(nome: 'Requeijão cremoso 200 g', preco: 7.45, quantidade: 20),
        PedidoItem(nome: 'Doce de leite pastoso 400 g', preco: 12.80, quantidade: 10),
      ],
      total: 277.00,
    ),
    Pedido(
      id: 1043, numero: '319', status: 'salvo',
      vendedorCodigo: '0001', vendedorNome: 'João Pereira',
      clienteNome: 'Padaria Pão Quente',
      enviadoEm: agora.subtract(const Duration(hours: 2)),
      alteradoEm: agora.subtract(const Duration(minutes: 25)),
      itens: const [
        PedidoItem(nome: 'Doce de leite pastoso 400 g', preco: 12.80, quantidade: 6),
        PedidoItem(nome: 'Manteiga com sal 200 g', preco: 11.90, quantidade: 12),
      ],
      total: 219.60,
    ),
    Pedido(
      id: 1044, numero: '320', status: 'salvo',
      vendedorCodigo: '0005', vendedorNome: 'Rafael Souza',
      clienteNome: 'Lanchonete da Praça',
      enviadoEm: agora.subtract(const Duration(minutes: 20)),
      itens: const [PedidoItem(nome: 'Manteiga com sal 200 g', preco: 11.90, quantidade: 8)],
      total: 95.20,
    ),
  ];
}

Future<List<Pedido>> _comProntos() async {
  final agora = DateTime.now();
  final abertos = await _emAberto();
  // pedido que ja foi marcado pronto e depois foi alterado: volta a "Em aberto"
  // com o selo "alterado depois de pronto".
  final alteradoDepois = Pedido(
    id: 1045,
    numero: '321',
    status: 'salvo',
    vendedorCodigo: '0002',
    vendedorNome: 'Maria Aparecida Santos',
    clienteNome: 'Empório Sabor de Minas',
    enviadoEm: agora.subtract(const Duration(hours: 6)),
    prontoEm: agora.subtract(const Duration(hours: 3)),
    prontoPor: 'Fábrica',
    alteradoEm: agora.subtract(const Duration(minutes: 40)),
    itens: const [
      PedidoItem(nome: 'Leite integral 1L', preco: 64.90, quantidade: 3)
    ],
    total: 194.70,
  );
  return [
    ...abertos,
    alteradoDepois,
    Pedido(
      id: 1040,
      numero: '316',
      status: 'pronto',
      vendedorCodigo: '0001',
      vendedorNome: 'João Pereira',
      clienteNome: 'Supermercado Irmãos Ferreira Ltda',
      enviadoEm: agora.subtract(const Duration(hours: 8)),
      prontoEm: agora.subtract(const Duration(hours: 1, minutes: 10)),
      prontoPor: 'Fábrica',
      itens: const [
        PedidoItem(nome: 'Leite integral 1L', preco: 64.90, quantidade: 10),
        PedidoItem(nome: 'Iogurte natural 170 g', preco: 3.29, quantidade: 48),
      ],
      total: 806.92,
    ),
    Pedido(
      id: 1039,
      numero: '315',
      status: 'pronto',
      vendedorCodigo: '0005',
      vendedorNome: 'Rafael Souza',
      clienteNome: 'Lanchonete da Praça',
      enviadoEm: agora.subtract(const Duration(hours: 4)),
      prontoEm: agora.subtract(const Duration(minutes: 12)),
      prontoPor: 'Fábrica',
      itens: const [
        PedidoItem(nome: 'Creme de leite 200 g', preco: 89.00, quantidade: 2)
      ],
      total: 178.00,
    ),
  ];
}

/// PNG de uma "assinatura" (rabisco) desenhada na hora.
Future<Uint8List> _pngAssinatura(double inclinacao) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
      const Rect.fromLTWH(0, 0, 400, 140), Paint()..color = Colors.white);
  final path = Path()..moveTo(20, 90);
  for (var i = 0; i < 7; i++) {
    path.quadraticBezierTo(50.0 + i * 50,
        20 + (i.isEven ? 0 : 100) * inclinacao, 70.0 + i * 50, 80);
  }
  c.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1A237E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round);
  final img = await rec.endRecording().toImage(400, 140);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _AbreDetalheAoMontar extends StatefulWidget {
  final Pedido pedido;
  const _AbreDetalheAoMontar(this.pedido);
  @override
  State<_AbreDetalheAoMontar> createState() => _AbreDetalheAoMontarState();
}

class _AbreDetalheAoMontarState extends State<_AbreDetalheAoMontar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => abrirDetalhesPedido(
          context,
          widget.pedido,
          buscar: (id) async =>
              (raw: <String, dynamic>{'id': id}, parsed: widget.pedido),
        ));
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

List<Widget> _abas() => [
      const ProducaoTab(carregar: _emAberto),
      const VendedoresTab(carregar: _vendedores),
      const ProdutosTab(carregar: _produtos),
      const PedidosTab(carregar: _pedidos),
      const ClientesTab(carregar: _clientes),
    ];

Widget _home(int indice) =>
    HomePage(abasDeTeste: _abas(), indiceInicial: indice, key: ValueKey('home$indice'));

const _nomes = ['producao', 'vendedores', 'produtos', 'pedidos', 'clientes'];

void main() {
  setUpAll(carregarFontesReais);

  testWidgets('login celular', (tester) async {
    await capturar(tester, const LoginPage(verificarSessaoSalva: false), 'login_celular',
        tamanho: _celular);
  });

  testWidgets('login windows', (tester) async {
    await capturar(tester, const LoginPage(verificarSessaoSalva: false), 'login_windows',
        tamanho: _windows);
  });

  for (var i = 0; i < _nomes.length; i++) {
    testWidgets('home ${_nomes[i]} windows', (tester) async {
      await capturar(tester, _home(i), 'home_${_nomes[i]}_windows', tamanho: _windows);
    });
    testWidgets('home ${_nomes[i]} celular', (tester) async {
      await capturar(tester, _home(i), 'home_${_nomes[i]}_celular', tamanho: _celular);
    });
  }

  testWidgets('home pedidos windows pequeno (trilho recolhido)', (tester) async {
    await capturar(tester, _home(3), 'home_pedidos_windows_1024', tamanho: _windowsPequeno);
  });

  testWidgets('home clientes vazio', (tester) async {
    await capturar(
      tester,
      HomePage(abasDeTeste: [
        const ProducaoTab(carregar: _emAberto),
        const VendedoresTab(carregar: _vendedores),
        const ProdutosTab(carregar: _produtos),
        const PedidosTab(carregar: _pedidos),
        ClientesTab(carregar: () async => <Cliente>[]),
      ], indiceInicial: 4),
      'home_clientes_vazio_windows',
      tamanho: _windows,
    );
  });

  testWidgets('producao estreita', (tester) async {
    await capturar(tester, const Scaffold(body: ProducaoTab(carregar: _emAberto)), 'producao_estreita',
        tamanho: _celular);
  });

  testWidgets('producao larga', (tester) async {
    await capturar(tester, _home(0), 'producao_larga', tamanho: _windows);
  });

  testWidgets('pedidos com filtro', (tester) async {
    await capturar(tester, const Scaffold(body: PedidosTab(carregar: _pedidos)), 'pedidos_filtro',
        tamanho: _celular);
  });

  testWidgets('producao com prontos estreita', (tester) async {
    await capturar(
        tester,
        const Scaffold(body: ProducaoTab(carregar: _comProntos)),
        'producao_com_prontos_estreita',
        tamanho: const Size(412, 2200));
  });

  testWidgets('producao com prontos larga', (tester) async {
    await capturar(
        tester,
        const HomePage(abasDeTeste: [
          ProducaoTab(carregar: _comProntos),
          VendedoresTab(carregar: _vendedores),
          ProdutosTab(carregar: _produtos),
          PedidosTab(carregar: _pedidos),
          ClientesTab(carregar: _clientes),
        ], indiceInicial: 0),
        'producao_com_prontos_larga',
        tamanho: const Size(1366, 1700));
  });

  testWidgets('detalhe com duas assinaturas', (tester) async {
    final pedido = await tester.runAsync(() async {
      final agora = DateTime.now();
      return Pedido(
        id: 1040,
        numero: '316',
        status: 'finalizado',
        vendedorCodigo: '0001',
        vendedorNome: 'João Pereira',
        clienteNome: 'Supermercado Irmãos Ferreira Ltda',
        enviadoEm: agora.subtract(const Duration(hours: 8)),
        prontoEm: agora.subtract(const Duration(hours: 3)),
        prontoPor: 'Fábrica',
        finalizadoEm: agora.subtract(const Duration(minutes: 30)),
        finalizadoPor: '0001',
        assinaturaPedidoBytes: await _pngAssinatura(1.0),
        assinaturaBytes: await _pngAssinatura(0.4),
        itens: const [
          PedidoItem(nome: 'Leite integral 1L', preco: 64.90, quantidade: 10),
          PedidoItem(
              nome: 'Iogurte natural 170 g', preco: 3.29, quantidade: 48),
        ],
        total: 806.92,
      );
    });
    await capturar(
        tester, _AbreDetalheAoMontar(pedido!), 'detalhe_duas_assinaturas',
        tamanho: const Size(480, 2400));
    await tester.pumpAndSettle();
    // As imagens só aparecem depois de alguns quadros reais: recaptura já com elas.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      File('build/visual/detalhe_duas_assinaturas.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    expect(find.text('Assinatura do pedido'), findsOneWidget);
    expect(find.text('Assinatura da entrega'), findsOneWidget);
    expect(find.byKey(const ValueKey('assinatura_pedido')), findsOneWidget);
    expect(find.byKey(const ValueKey('assinatura_entrega')), findsOneWidget);
    expect(find.text('Pronto por'), findsOneWidget);
  });
}
