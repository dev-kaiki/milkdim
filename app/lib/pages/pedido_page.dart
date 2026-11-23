// lib/pages/pedido_page.dart

import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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

  const PedidoPage({super.key, required this.vendedor, this.dadosParaCaptura});

  @override
  State<PedidoPage> createState() => _PedidoPageState();
}

class _PedidoPageState extends State<PedidoPage> {
  Map<Produto, int> carrinho = {};
  Map<Produto, TextEditingController> _qtdControllers = {};
  Uint8List? _assinatura; // PNG/JPEG bytes prontos para gravar e gerar PDF

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

  // ====== Grava assinatura no Documents/signatures e retorna caminho ======
  Future<String?> _gravarAssinaturaLocal(Uint8List? bytes, {required String numero}) async {
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getApplicationDocumentsDirectory();
    final sigDir = Directory('${dir.path}/signatures');
    if (!await sigDir.exists()) {
      await sigDir.create(recursive: true);
      // ignore: avoid_print
      print('[PEDIDO] diretório criado: ${sigDir.path}');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeNum = (numero.isEmpty ? 's_n' : numero)
        .replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    final file = File('${sigDir.path}/sig_${safeNum}_$ts.png');
    await file.writeAsBytes(bytes, flush: true);
    // ignore: avoid_print
    print('[PEDIDO] assinatura gravada (${bytes.length} bytes) em: ${file.path}');
    return file.path;
  }

  /// Salva/finaliza e fecha a página retornando o `status`
  Future<void> _salvarPedido(String status) async {
    if (carregando) return;
    if (nomeCtrl.text.trim().isEmpty) {
      _showMsg('Preencha o nome do cliente!');
      return;
    }

    final produtosList = carrinho.entries
        .where((e) => e.value > 0)
        .map((e) => {
      'nome': e.key.nome,
      'preco': e.key.preco,
      'quantidade': e.value,
      'subtotal': (e.key.preco * e.value),
    })
        .toList();

    if (produtosList.isEmpty) {
      _showMsg('Adicione ao menos um produto ao pedido!');
      return;
    }
    if (status == 'finalizado' && (_assinatura == null || _assinatura!.isEmpty)) {
      _showMsg('É obrigatório assinar para finalizar!');
      return;
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

      final caminhoAss =
      await _gravarAssinaturaLocal(_assinatura, numero: numeroPedidoCtrl.text.trim());

      final pedido = pedidoDaTela(
        base: {
          'vendedor_codigo': widget.vendedor['codigo'],
          'vendedor_nome': widget.vendedor['nome'],
        },
        numero: numeroPedidoCtrl.text.trim(),
        produtos: produtosList,
        total: total,
        status: status,
        datahora: DateTime.now().toUtc().toIso8601String(),
        clienteId: _clienteId,
        cliente: _camposCliente(),
        // os bytes vão ao servidor; o caminho fica só no aparelho
        assinatura: _assinatura,
        assinaturaPath: caminhoAss,
      );

      // Grava no aparelho na hora (fora da trava: um pedido novo não pode
      // estar num envio em andamento) e, se finalizado, tenta enviar. O helper
      // remove `assinatura_path` do payload e o preserva no SQLite.
      final r = await gravarPedidoEEnviar(pedido, novo: true);

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
                child: ResumoPedido(
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
                  assinatura: _assinatura,
                  ocupado: carregando,
                  onAssinar: () async {
                    // PODE VOLTAR QUALQUER FORMATO -> convertemos
                    final dynamic assinaturaAny = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => assinatura.AssinaturaPage(
                          assinatura: _assinatura,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    final bytes = signatureToImageBytes(assinaturaAny);
                    if (bytes != null && bytes.isNotEmpty) {
                      setState(() {
                        _assinatura = bytes;
                      });
                    }
                  },
                  onSalvar: () {
                    Navigator.of(context).pop();
                    _salvarPedido('salvo');
                  },
                  onFinalizar: () {
                    Navigator.of(context).pop();
                    _salvarPedido('finalizado');
                  },
                ),
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
