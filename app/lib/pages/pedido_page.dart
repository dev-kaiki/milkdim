// lib/pages/pedido_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/produto.dart';
import '../utils/db.dart';
import '../utils/pedido_da_tela.dart';
import '../utils/produto_service.dart';
import '../utils/regras_pedido.dart';
import '../utils/repetir_pedido.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // <- signatureToImageBytes / assinaturaToBytes
import '../widgets/pedido_ui.dart';
import '../widgets/pedidos_anteriores.dart';
import 'assinatura_page.dart' as assinatura; // alias para evitar ambiguidade

class PedidoPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Só para a captura visual: quando informado, usa estes clientes e produtos
  /// e não consulta SQLite nem rede.
  final ({List<Map<String, dynamic>> clientes, List<Produto> produtos})? dadosParaCaptura;

  /// Para teste: no lugar de abrir a `AssinaturaPage`.
  final PedirAssinatura? pedirAssinatura;

  /// Para teste: no lugar de `gravarPedidoEEnviar`.
  final GravarPedido? gravar;

  /// Para teste: no lugar de `listarPedidosDoCliente`.
  final Future<List<Map<String, dynamic>>> Function(int clienteId)? carregarPedidosDoCliente;

  /// "Repetir": pedido de onde partir. Quando clientes e produtos terminam de
  /// carregar, a tela abre com o cliente e as quantidades dele. O número do
  /// pedido continua sendo o próximo.
  final Map<String, dynamic>? partirDe;

  const PedidoPage({
    super.key,
    required this.vendedor,
    this.partirDe,
    this.dadosParaCaptura,
    this.pedirAssinatura,
    this.gravar,
    this.carregarPedidosDoCliente,
  });

  @override
  State<PedidoPage> createState() => _PedidoPageState();
}

class _PedidoPageState extends State<PedidoPage> {
  Map<Produto, int> carrinho = {};
  Map<Produto, TextEditingController> _qtdControllers = {};
  /// Assinatura do pedido (PNG/JPEG). A da entrega é pedida depois, ao
  /// registrar a entrega na edição.
  Uint8List? _assinaturaPedido;

  /// Itens e cliente que a [_assinaturaPedido] cobre (como estavam na tela
  /// quando o cliente assinou).
  Map<String, dynamic>? _assinadoSobre;

  /// Os itens como a tela grava (só os com quantidade).
  List<Map<String, dynamic>> _itensDaTela() => carrinho.entries
      .where((e) => e.value > 0)
      .map((e) => <String, dynamic>{
            'nome': e.key.nome,
            'preco': e.key.preco,
            'quantidade': e.value,
            'subtotal': (e.key.preco * e.value),
          })
      .toList();

  /// Itens e cliente da tela agora (o que a assinatura do pedido cobre).
  Map<String, dynamic> _itensEClienteDaTela() => {
        'produtos': _itensDaTela(),
        'cliente_id': _clienteId,
        'cliente_nome': nomeCtrl.text.trim(),
      };

  void _guardarAssinaturaPedido(Uint8List bytes) {
    _assinaturaPedido = bytes;
    _assinadoSobre = _itensEClienteDaTela();
  }

  /// A [_assinaturaPedido] foi dada para os itens e o cliente que estão na
  /// tela agora?
  bool get _assinaturaCobreATela =>
      _assinaturaPedido != null &&
      _assinaturaPedido!.isNotEmpty &&
      _assinadoSobre != null &&
      !itensOuClienteMudaram(_assinadoSobre!, _itensEClienteDaTela());

  // CLIENTE
  int? _clienteId;
  DateTime? _ultimoPedido;

  /// Pedidos anteriores do cliente escolhido (quadro "Partir de um pedido anterior").
  List<Map<String, dynamic>> _anteriores = [];

  // CAMPOS CLIENTE
  final nomeCtrl = TextEditingController();
  final nomeFantasiaCtrl = TextEditingController();
  final telefoneCtrl = TextEditingController();
  final whatsappCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final enderecoCtrl = TextEditingController();
  final cidadeCtrl = TextEditingController();
  final cpfCnpjCtrl = TextEditingController();
  final inscEstadualCtrl = TextEditingController();
  final cepCtrl = TextEditingController();
  final anotacaoCtrl = TextEditingController();
  final numeroPedidoCtrl = TextEditingController();

  bool carregando = false;
  bool carregandoProdutos = true;
  List<Map<String, dynamic>> clientes = [];
  List<Produto> produtos = [];
  int ultimoNumeroPedido = 1;

  // "Repetir": só parte do pedido de origem uma vez, depois que clientes e
  // produtos chegaram.
  bool _clientesProntos = false;
  bool _partiuDe = false;

  double get total =>
      carrinho.entries.fold(0.0, (s, e) => s + e.key.preco * (e.value));

  @override
  void initState() {
    super.initState();
    final captura = widget.dadosParaCaptura;
    if (captura != null) {
      clientes = captura.clientes;
      _clientesProntos = true;
      numeroPedidoCtrl.text = ultimoNumeroPedido.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarProdutos(captura.produtos));
      return;
    }
    _carregarClientes();
    _carregarProdutos();
    _carregarProximoNumeroPedido();
    // ignore: avoid_print
    print('[PEDIDO] initState | vendedor=${
        {'codigo': widget.vendedor['codigo'], 'nome': widget.vendedor['nome']}
    }');
  }

  @override
  void dispose() {
    nomeCtrl.dispose();
    nomeFantasiaCtrl.dispose();
    telefoneCtrl.dispose();
    whatsappCtrl.dispose();
    emailCtrl.dispose();
    enderecoCtrl.dispose();
    cidadeCtrl.dispose();
    cpfCnpjCtrl.dispose();
    inscEstadualCtrl.dispose();
    cepCtrl.dispose();
    anotacaoCtrl.dispose();
    numeroPedidoCtrl.dispose();
    for (final c in _qtdControllers.values) {
      c.dispose();
    }
    // ignore: avoid_print
    print('[PEDIDO] dispose()');
    super.dispose();
  }

  Future<void> _carregarProximoNumeroPedido() async {
    final ultimo = await buscarUltimoNumeroPedido();
    final proximo = (ultimo ?? 0) + 1;
    if (!mounted) return;
    setState(() {
      ultimoNumeroPedido = proximo;
      numeroPedidoCtrl.text = proximo.toString();
    });
    // ignore: avoid_print
    print('[PEDIDO] próximo nº pedido calculado: $proximo (último local=$ultimo)');
  }

  Future<void> _carregarClientes() async {
    final cli = await listarClientes();
    if (!mounted) return;
    setState(() => clientes = cli);
    _clientesProntos = true;
    // ignore: avoid_print
    print('[PEDIDO] clientes carregados: ${clientes.length}');
    _tentarPartirDe();
  }

  Future<void> _carregarProdutos() async {
    setState(() => carregandoProdutos = true);
    // ignore: avoid_print
    print('[PEDIDO] carregando produtos...');
    final produtosDb = await buscarProdutosOnlineOuLocal();
    _aplicarProdutos(produtosDb);
  }

  void _aplicarProdutos(List<Produto> produtosDb) {
    final novoCarrinho = <Produto, int>{};
    final novosControllers = <Produto, TextEditingController>{};

    for (var p in produtosDb) {
      final qtd = carrinho[p] ?? 0;
      novoCarrinho[p] = qtd;
      final ctrl = TextEditingController(text: qtd > 0 ? qtd.toString() : '');
      ctrl.addListener(() {
        final val = int.tryParse(ctrl.text) ?? 0;
        setState(() {
          carrinho[p] = val < 0 ? 0 : val;
        });
      });
      novosControllers[p] = ctrl;
    }

    for (final c in _qtdControllers.values) {
      c.dispose();
    }

    if (!mounted) return;
    setState(() {
      produtos = produtosDb;
      carrinho = novoCarrinho;
      _qtdControllers = novosControllers;
      carregandoProdutos = false;
    });
    // ignore: avoid_print
    print('[PEDIDO] produtos carregados: ${produtos.length}');
    _tentarPartirDe();
  }

  /// "Repetir": com clientes e produtos prontos, preenche a tela com o cliente
  /// e as quantidades de [PedidoPage.partirDe] (sem perguntar: a tela está vazia).
  void _tentarPartirDe() {
    final origem = widget.partirDe;
    if (origem == null || _partiuDe || !_clientesProntos || carregandoProdutos) return;
    _partiuDe = true;
    final id = (origem['cliente_id'] as num?)?.toInt();
    Map<String, dynamic>? cliente;
    for (final c in clientes) {
      if ((c['id'] as num?)?.toInt() == id) {
        cliente = c;
        break;
      }
    }
    if (cliente == null) {
      _showMsg('Este cliente não está mais cadastrado');
      return;
    }
    _aplicarCliente(cliente);
    _aplicarPreenchimento(preencherDePedido(origem['produtos'], produtos));
  }

  Future<void> _recarregarUltimoPedido() async {
    if (_clienteId == null) {
      if (!mounted) return;
      setState(() => _ultimoPedido = null);
      return;
    }
    final last = await getUltimoPedidoCliente(_clienteId!);
    if (!mounted) return;
    setState(() => _ultimoPedido = last);
    // ignore: avoid_print
    print('[PEDIDO] ultimoPedido do cliente $_clienteId => ${_ultimoPedido?.toIso8601String()}');
  }

  Future<void> _autoPreencherClientePorNome() async {
    // Na captura/teste os clientes já vieram prontos: não consulta o SQLite.
    if (widget.dadosParaCaptura == null) await _carregarClientes();
    if (!mounted) return;
    // ignore: avoid_print
    print('[PEDIDO] buscar cliente por nome');
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController buscaCtrl = TextEditingController();
        List<Map<String, dynamic>> resultados = List.from(clientes);
        return StatefulBuilder(
          builder: (context, setModalState) {
            void buscar() {
              final busca = buscaCtrl.text.trim().toLowerCase();
              setModalState(() {
                resultados = clientes
                    .where((c) => (c['nome'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(busca))
                    .toList();
              });
            }

            return AlertDialog(
              title: const Text('Buscar cliente por nome'),
              content: ConteudoBuscaCliente(
                controller: buscaCtrl,
                resultados: resultados,
                onBuscar: buscar,
                onEscolher: (cli) {
                  Navigator.pop(context, cli);
                },
              ),
            );
          },
        );
      },
    ).then((clienteSelecionado) async {
      if (clienteSelecionado is Map<String, dynamic>) {
        await _aplicarCliente(clienteSelecionado);
      }
    });
  }

  /// Preenche os campos com o cliente escolhido e carrega o último pedido e os
  /// pedidos anteriores dele.
  Future<void> _aplicarCliente(Map<String, dynamic> cli) async {
    _clienteId = (cli['id'] as num?)?.toInt();
    nomeCtrl.text = cli['nome'] ?? '';
    nomeFantasiaCtrl.text = cli['nome_fantasia'] ?? '';
    telefoneCtrl.text = cli['telefone'] ?? '';
    whatsappCtrl.text = cli['whatsapp'] ?? '';
    emailCtrl.text = cli['email'] ?? '';
    enderecoCtrl.text = cli['endereco'] ?? '';
    cidadeCtrl.text = cli['cidade'] ?? '';
    cpfCnpjCtrl.text = cli['cpf_cnpj'] ?? '';
    inscEstadualCtrl.text = cli['insc_estadual'] ?? '';
    cepCtrl.text = cli['cep'] ?? '';
    anotacaoCtrl.text = cli['anotacao'] ?? '';
    final id = _clienteId;
    // Esvazia já: não deixa o quadro do cliente anterior na tela enquanto carrega.
    if (mounted) setState(() => _anteriores = []);
    if (widget.dadosParaCaptura == null) await _recarregarUltimoPedido();
    var anteriores = <Map<String, dynamic>>[];
    if (id != null) {
      try {
        anteriores = await (widget.carregarPedidosDoCliente ?? listarPedidosDoCliente)(id);
      } catch (e) {
        // ignore: avoid_print
        print('[PEDIDO] erro ao carregar pedidos anteriores: $e');
      }
    }
    if (!mounted || _clienteId != id) return; // trocou de cliente no meio
    setState(() => _anteriores = anteriores);
    // ignore: avoid_print
    print('[PEDIDO] cliente selecionado => $_clienteId');
  }

  /// Põe em cada produto da tela a quantidade de [p] (ou 0) e avisa dos que
  /// ficaram de fora.
  void _aplicarPreenchimento(Preenchimento p) {
    setState(() {
      for (final prod in carrinho.keys.toList()) {
        final q = p.quantidades[prod] ?? 0;
        carrinho[prod] = q;
        _qtdControllers[prod]?.text = q > 0 ? q.toString() : '';
      }
    });
    if (p.foraDoPedido.isNotEmpty) {
      _showMsg('Ficaram de fora (não estão mais à venda): ${p.foraDoPedido.join(', ')}',
          tipo: MdTipo.atencao);
    }
  }

  /// "Usar" um pedido anterior: só pergunta se já há quantidades na tela.
  Future<void> _usarPedidoAnterior(Map<String, dynamic> pedido) async {
    // Gravando: a tela não pode mudar por baixo do pedido que já foi montado.
    if (carregando) return;
    if (carrinho.values.any((q) => q > 0)) {
      final trocar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('Trocar as quantidades da tela pelas deste pedido?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar')),
          ],
        ),
      );
      if (trocar != true || !mounted || carregando) return;
    }
    _aplicarPreenchimento(preencherDePedido(pedido['produtos'], produtos));
  }

  /// Abre a tela de assinatura do pedido (com o [aviso], se houver) e devolve
  /// a imagem, ou null se o vendedor voltou sem assinar.
  Future<Uint8List?> _pedirAssinatura({String? aviso}) async {
    final injetada = widget.pedirAssinatura;
    if (injetada != null) return injetada(TipoAssinatura.pedido, aviso: aviso);
    // PODE VOLTAR QUALQUER FORMATO -> convertemos
    final dynamic ret = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => assinatura.AssinaturaPage(
          assinatura: _assinaturaPedido,
          titulo: TipoAssinatura.pedido.titulo,
          aviso: aviso,
        ),
      ),
    );
    final bytes = signatureToImageBytes(ret);
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  /// "Enviar pedido" ([enviar]): sem a assinatura do pedido, pede ao cliente
  /// antes (desistiu: nada é gravado e o formulário continua); grava `salvo`
  /// com a assinatura e envia.
  /// "Salvar rascunho": grava `salvo` só no aparelho (`so_local = 1`), sem
  /// enviar e sem pedir assinatura. A assinatura do pedido já colhida vai
  /// junto quando ainda cobre os itens e o cliente da tela (a linha gravada é
  /// o que o cliente assinou); senão não vai.
  /// Gravou: fecha a página devolvendo o `status`.
  Future<void> _salvarPedido({required bool enviar}) async {
    if (carregando) return;
    if (nomeCtrl.text.trim().isEmpty) {
      _showMsg('Preencha o nome do cliente!');
      return;
    }

    final produtosList = _itensDaTela();

    if (produtosList.isEmpty) {
      _showMsg('Adicione ao menos um produto ao pedido!');
      return;
    }
    if (enviar) {
      String? aviso;
      if (_assinaturaPedido == null || _assinaturaPedido!.isEmpty) {
        aviso = kAvisoAssinarPedido;
      } else if (_assinadoSobre == null ||
          itensOuClienteMudaram(_assinadoSobre!, _itensEClienteDaTela())) {
        // Assinou antes e os itens ou o cliente mudaram depois: a assinatura
        // não cobre o que vai ser enviado.
        aviso = kAvisoAssinarPedidoDeNovo;
        setState(() {
          _assinaturaPedido = null;
          _assinadoSobre = null;
        });
      }
      if (aviso != null) {
        final bytes = await _pedirAssinatura(aviso: aviso);
        if (!mounted || bytes == null) return;
        setState(() => _guardarAssinaturaPedido(bytes));
      }
    }

    setState(() => carregando = true);

    try {
      // Número já usado (no aparelho ou no servidor): troca o número e não grava.
      final numero = numeroPedidoCtrl.text.trim();
      final vendedorCodigo = widget.vendedor['codigo']?.toString() ?? '';
      if (widget.dadosParaCaptura == null &&
          !await numeroLivreParaVendedor(numero, vendedorCodigo)) {
        await _sugerirProximoNumero(vendedorCodigo);
        if (!mounted) return;
        _showMsg(kMsgNumeroEmUso);
        setState(() => carregando = false);
        return;
      }

      final pedido = {
        ...pedidoDaTela(
          base: {
            'vendedor_codigo': widget.vendedor['codigo'],
            'vendedor_nome': widget.vendedor['nome'],
          },
          numero: numeroPedidoCtrl.text.trim(),
          produtos: produtosList,
          total: total,
          status: 'salvo',
          datahora: DateTime.now().toUtc().toIso8601String(),
          clienteId: _clienteId,
          cliente: _camposCliente(),
          // a entrega é assinada depois, ao registrar a entrega
          assinatura: null,
          assinaturaPath: null,
          // os bytes vão no SQLite e ao servidor (sem arquivo no aparelho);
          // no rascunho, só a que cobre a tela
          assinaturaPedido: _assinaturaCobreATela ? _assinaturaPedido : null,
        ),
        // rascunho: fica só no aparelho até o pedido ser enviado
        if (!enviar) 'so_local': 1,
        // rascunho sem assinatura que cubra a tela: nada de assinatura velha
        // de outra linha com o mesmo número
        if (!enviar && !_assinaturaCobreATela) kLimparAssinaturaPedido: true,
      };
      final status = pedido['status'] as String;

      // Grava no aparelho na hora (fora da trava: um pedido novo não pode
      // estar num envio em andamento) e, se não for rascunho, tenta enviar.
      final r = await (widget.gravar ?? gravarPedidoEEnviar)(pedido, novo: true);

      if (!mounted) return;
      final msg = mensagemGravacao(r, status);
      if (msg != null) {
        _showMsg(msg, isError: gravacaoEhAviso(r));
      }
      // ignore: avoid_print
      print('[PEDIDO] concluído ($r) -> pop("$status")');
      Navigator.pop(context, status);
    } on NumeroEmUso catch (e) {
      // Nada foi gravado: o formulário fica aberto com os dados para trocar o número.
      // ignore: avoid_print
      print('[PEDIDO] $e');
      _showMsg(kMsgNumeroEmUso);
      if (mounted) setState(() => carregando = false);
    } catch (e) {
      // Só chega aqui se a gravação no aparelho falhou.
      // ignore: avoid_print
      print('[PEDIDO] erro ao salvar pedido: $e');
      _showMsg('Erro ao salvar pedido.');
      if (mounted) setState(() => carregando = false);
    }
  }

  Map<String, String> _camposCliente() => {
        'cliente_nome': nomeCtrl.text.trim(),
        'cliente_nome_fantasia': nomeFantasiaCtrl.text.trim(),
        'cliente_telefone': telefoneCtrl.text.trim(),
        'cliente_whatsapp': whatsappCtrl.text.trim(),
        'cliente_email': emailCtrl.text.trim(),
        'cliente_endereco': enderecoCtrl.text.trim(),
        'cliente_cidade': cidadeCtrl.text.trim(),
        'cliente_cpf_cnpj': cpfCnpjCtrl.text.trim(),
        'cliente_insc_estadual': inscEstadualCtrl.text.trim(),
        'cliente_cep': cepCtrl.text.trim(),
        'cliente_anotacao': anotacaoCtrl.text.trim(),
      };

  /// Preenche o campo com o próximo número livre (no máximo 20 tentativas).
  Future<void> _sugerirProximoNumero(String vendedorCodigo) async {
    final n = await proximoNumeroLivreDoVendedor(vendedorCodigo);
    if (n == null || !mounted) return;
    setState(() {
      ultimoNumeroPedido = int.tryParse(n) ?? ultimoNumeroPedido;
      numeroPedidoCtrl.text = n;
    });
  }

  void _abrirPopupResumo() {
    // ignore: avoid_print
    print('[PEDIDO] abrir popup de resumo');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: MdSpace.xl,
                right: MdSpace.xl,
                bottom: MediaQuery.of(context).viewInsets.bottom + MdSpace.xl,
              ),
              child: MdContentWidth(
                maxWidth: 640,
                // StatefulBuilder: a prévia da assinatura atualiza na folha aberta.
                child: StatefulBuilder(builder: (folha, setFolha) => ResumoPedido(
                  numero: numeroPedidoCtrl.text,
                  cliente: nomeCtrl.text,
                  ultimoPedido: _ultimoPedido,
                  campos: [
                    ('Nome Fantasia', nomeFantasiaCtrl.text),
                    ('Telefone', telefoneCtrl.text),
                    ('WhatsApp', whatsappCtrl.text),
                    ('Email', emailCtrl.text),
                    ('Endereço', enderecoCtrl.text),
                    ('Cidade', cidadeCtrl.text),
                    ('CPF/CNPJ', cpfCnpjCtrl.text),
                    ('Insc. Estadual', inscEstadualCtrl.text),
                    ('CEP', cepCtrl.text),
                    ('Anotação', anotacaoCtrl.text),
                  ],
                  vendedor: (widget.vendedor['nome'] ?? '-').toString(),
                  itens: [
                    for (final e in carrinho.entries.where((e) => e.value > 0))
                      (nome: e.key.nome, quantidade: e.value, subtotal: e.key.preco * e.value),
                  ],
                  total: total,
                  assinatura: _assinaturaPedido,
                  ocupado: carregando,
                  onAssinar: () async {
                    final bytes = await _pedirAssinatura();
                    if (!mounted || bytes == null) return;
                    setState(() => _guardarAssinaturaPedido(bytes));
                    if (folha.mounted) setFolha(() {});
                  },
                  principal: (
                    rotulo: 'Enviar pedido',
                    icone: Icons.send_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _salvarPedido(enviar: true);
                    },
                  ),
                  secundario: (
                    rotulo: 'Salvar rascunho',
                    icone: Icons.save_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _salvarPedido(enviar: false);
                    },
                  ),
                )),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _campoCliente({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    VoidCallback? suffixIconTap,
  }) {
    final isNome = label == 'Nome';
    return Padding(
      padding: const EdgeInsets.only(bottom: MdSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              prefixIcon: Icon(icon),
              suffixIcon: suffixIconTap != null
                  ? IconButton(
                      icon: const Icon(Icons.person_search_outlined),
                      tooltip: 'Buscar cliente',
                      color: MdColors.primaryStrong,
                      onPressed: suffixIconTap)
                  : null,
              labelText: label,
            ),
          ),
          if (isNome)
            Padding(
              padding: const EdgeInsets.only(top: MdSpace.sm, left: MdSpace.xs),
              child: Row(
                children: [
                  Text('Último pedido', style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  SeloUltimoPedido(ultimoPedido: _ultimoPedido),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showMsg(String msg, {bool isError = true, MdTipo? tipo}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: tipo ?? (isError ? MdTipo.erro : MdTipo.sucesso));
  }

  // ---------- Helpers de layout responsivo ----------
  Widget _twoUp(bool horizontal, Widget left, Widget right) {
    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: MdSpace.md),
          Expanded(child: right),
        ],
      );
    }
    return Column(
      children: [
        left,
        right,
      ],
    );
  }

  int _gridColumns(double width) {
    if (width >= 1000) return 3;
    if (width >= 700) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final twoCols = width >= 700;
    final gridCols = _gridColumns(width);
    final carregandoTela = clientes.isEmpty || carregandoProdutos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fazer Pedido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar produtos',
            onPressed: _carregarProdutos,
          ),
          const SizedBox(width: MdSpace.xs),
        ],
      ),
      bottomNavigationBar: !carregandoTela && total > 0
          ? BarraResumo(
              total: total,
              onPressed: carregando ? null : _abrirPopupResumo,
              ocupado: carregando,
            )
          : null,
      body: carregandoTela
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(MdSpace.lg),
              child: MdContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MdSectionHeader(titulo: 'Dados do Cliente'),
                    MdCard(
                      padding: const EdgeInsets.fromLTRB(
                          MdSpace.lg, MdSpace.lg, MdSpace.lg, MdSpace.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _twoUp(
                            twoCols,
                            _campoCliente(
                              icon: Icons.numbers,
                              label: 'Nº Pedido',
                              controller: numeroPedidoCtrl,
                              keyboardType: TextInputType.number,
                            ),
                            _campoCliente(
                              icon: Icons.person_outline,
                              label: 'Nome',
                              controller: nomeCtrl,
                              suffixIconTap: _autoPreencherClientePorNome,
                            ),
                          ),
                          _campoCliente(
                              icon: Icons.storefront_outlined,
                              label: 'Nome Fantasia',
                              controller: nomeFantasiaCtrl),
                          _twoUp(
                            twoCols,
                            _campoCliente(
                                icon: Icons.phone_outlined,
                                label: 'Telefone',
                                controller: telefoneCtrl,
                                keyboardType: TextInputType.phone),
                            _campoCliente(
                              icon: Icons.sms_outlined,
                              label: 'WhatsApp',
                              controller: whatsappCtrl,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          _campoCliente(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress),
                          _campoCliente(
                              icon: Icons.home_outlined,
                              label: 'Endereço',
                              controller: enderecoCtrl),
                          _twoUp(
                            twoCols,
                            _campoCliente(
                                icon: Icons.location_city_outlined,
                                label: 'Cidade',
                                controller: cidadeCtrl),
                            _campoCliente(
                                icon: Icons.map_outlined,
                                label: 'CEP',
                                controller: cepCtrl,
                                keyboardType: TextInputType.number),
                          ),
                          _twoUp(
                            twoCols,
                            _campoCliente(
                                icon: Icons.credit_card,
                                label: 'CPF/CNPJ',
                                controller: cpfCnpjCtrl,
                                keyboardType: TextInputType.number),
                            _campoCliente(
                                icon: Icons.assignment_outlined,
                                label: 'Insc. Estadual',
                                controller: inscEstadualCtrl),
                          ),
                          _campoCliente(
                              icon: Icons.notes,
                              label: 'Anotação',
                              controller: anotacaoCtrl,
                              maxLines: 2),
                        ],
                      ),
                    ),
                    QuadroPedidosAnteriores(
                      pedidos: _anteriores,
                      onUsar: _usarPedidoAnterior,
                      habilitado: !carregando,
                    ),
                    const SizedBox(height: MdSpace.xl),
                    const MdSectionHeader(titulo: 'Produtos'),

                    // Grade de produtos
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: produtos.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridCols,
                        crossAxisSpacing: MdSpace.md,
                        mainAxisSpacing: MdSpace.md,
                        mainAxisExtent: 92,
                      ),
                      itemBuilder: (ctx, i) {
                        final p = produtos[i];
                        final controller = _qtdControllers[p]!;
                        return ProdutoQtdTile(
                          nome: p.nome,
                          preco: p.preco,
                          quantidade: carrinho[p] ?? 0,
                          controller: controller,
                          habilitado: !carregando,
                          onChanged: (value) {
                            final val = int.tryParse(value) ?? 0;
                            setState(() {
                              carrinho[p] = val < 0 ? 0 : val;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: MdSpace.lg),
                  ],
                ),
              ),
            ),
    );
  }
}
