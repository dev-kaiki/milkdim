// lib/pages/pedido_page.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/produto.dart';
import '../utils/db.dart';
import '../utils/pedido_da_tela.dart';
import '../utils/produto_service.dart';
import '../utils/regras_pedido.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // <- signatureToImageBytes / assinaturaToBytes
import '../widgets/pedido_ui.dart';
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

  const PedidoPage({
    super.key,
    required this.vendedor,
    this.dadosParaCaptura,
    this.pedirAssinatura,
    this.gravar,
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

  // CLIENTE
  int? _clienteId;
  DateTime? _ultimoPedido;

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

  double get total =>
      carrinho.entries.fold(0.0, (s, e) => s + e.key.preco * (e.value));

  @override
  void initState() {
    super.initState();
    final captura = widget.dadosParaCaptura;
    if (captura != null) {
      clientes = captura.clientes;
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
    // ignore: avoid_print
    print('[PEDIDO] clientes carregados: ${clientes.length}');
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
    await _carregarClientes();
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
        _clienteId = (clienteSelecionado['id'] as num?)?.toInt();
        nomeCtrl.text = clienteSelecionado['nome'] ?? '';
        nomeFantasiaCtrl.text = clienteSelecionado['nome_fantasia'] ?? '';
        telefoneCtrl.text = clienteSelecionado['telefone'] ?? '';
        whatsappCtrl.text = clienteSelecionado['whatsapp'] ?? '';
        emailCtrl.text = clienteSelecionado['email'] ?? '';
        enderecoCtrl.text = clienteSelecionado['endereco'] ?? '';
        cidadeCtrl.text = clienteSelecionado['cidade'] ?? '';
        cpfCnpjCtrl.text = clienteSelecionado['cpf_cnpj'] ?? '';
        inscEstadualCtrl.text = clienteSelecionado['insc_estadual'] ?? '';
        cepCtrl.text = clienteSelecionado['cep'] ?? '';
        anotacaoCtrl.text = clienteSelecionado['anotacao'] ?? '';
        await _recarregarUltimoPedido();
        if (mounted) setState(() {});
        // ignore: avoid_print
        print('[PEDIDO] cliente selecionado => $_clienteId');
      }
    });
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
  /// assinatura e sem enviar.
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
          // os bytes vão no SQLite e ao servidor (sem arquivo no aparelho)
          assinaturaPedido: enviar ? _assinaturaPedido : null,
        ),
        // rascunho: fica só no aparelho até o cliente assinar e o pedido ir
        if (!enviar) 'so_local': 1,
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

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: isError ? MdTipo.erro : MdTipo.sucesso);
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
