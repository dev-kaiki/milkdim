// lib/pages/pedido_edit_page.dart

import 'dart:convert'; // jsonDecode
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/produto.dart';
import '../utils/produto_service.dart';
import '../utils/db.dart';
import '../utils/pedido_da_tela.dart';
import '../utils/regras_pedido.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // assinaturaToBytes / signatureToImageBytes / imageTypeFromBytes
import '../widgets/pedido_ui.dart';
import 'assinatura_page.dart';

class PedidoPageEdit extends StatefulWidget {
  final Map<String, dynamic> pedido;

  /// Só para a captura visual: quando informado, usa estes produtos e não
  /// consulta SQLite nem rede.
  final List<Produto>? produtosParaCaptura;

  const PedidoPageEdit({super.key, required this.pedido, this.produtosParaCaptura});

  @override
  State<PedidoPageEdit> createState() => _PedidoPageEditState();
}

class _PedidoPageEditState extends State<PedidoPageEdit> {
  final Map<Produto, int> carrinho = {};
  final Map<Produto, TextEditingController> _qtdControllers = {};
  List<Produto> produtos = [];

  /// Assinatura PNG/JPEG (bytes) para preview/PDF e salvamento
  Uint8List? _assinatura;

  // cliente selecionado
  int? _clienteId;
  DateTime? _ultimoPedido; // para o badge

  final numeroPedidoCtrl = TextEditingController();
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

  bool processando = false;
  bool carregandoProdutos = true;
  List<Map<String, dynamic>> clientes = [];

  @override
  void initState() {
    super.initState();

    // Nº pedido vindo do registro
    numeroPedidoCtrl.text = widget.pedido['numero']?.toString() ?? '';

    // Cliente vindo do pedido
    _clienteId = (widget.pedido['cliente_id'] as num?)?.toInt();
    nomeCtrl.text = widget.pedido['cliente_nome'] ?? '';
    nomeFantasiaCtrl.text = widget.pedido['cliente_nome_fantasia'] ?? '';
    telefoneCtrl.text = widget.pedido['cliente_telefone'] ?? '';
    whatsappCtrl.text = widget.pedido['cliente_whatsapp'] ?? '';
    emailCtrl.text = widget.pedido['cliente_email'] ?? '';
    enderecoCtrl.text = widget.pedido['cliente_endereco'] ?? '';
    cidadeCtrl.text = widget.pedido['cliente_cidade'] ?? '';
    cpfCnpjCtrl.text = widget.pedido['cliente_cpf_cnpj'] ?? '';
    inscEstadualCtrl.text = widget.pedido['cliente_insc_estadual'] ?? '';
    cepCtrl.text = widget.pedido['cliente_cep'] ?? '';
    anotacaoCtrl.text = widget.pedido['cliente_anotacao'] ?? '';

    // LOG
    // ignore: avoid_print
    print('[EDIT] initState | pedido=${widget.pedido}');

    // Carrega assinatura existente (prioriza arquivo local) e normaliza para imagem
    _initAssinatura();

    final captura = widget.produtosParaCaptura;
    if (captura != null) {
      _inicializarCarrinhoEControllers(captura);
      produtos = captura;
      carregandoProdutos = false;
      return;
    }

    _carregarClientes();
    _carregarProdutos();
    _recarregarUltimoPedido();
  }

  @override
  void dispose() {
    for (final c in _qtdControllers.values) {
      c.dispose();
    }
    numeroPedidoCtrl.dispose();
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
    // ignore: avoid_print
    print('[EDIT] dispose()');
    super.dispose();
  }

  Future<void> _initAssinatura() async {
    try {
      final path = widget.pedido['assinatura_path'];
      if (path is String && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final img = signatureToImageBytes(bytes);
          if (img != null && img.isNotEmpty) {
            setState(() => _assinatura = img);
            // ignore: avoid_print
            print('[EDIT] assinatura carregada do arquivo (${img.length} bytes, tipo=${imageTypeFromBytes(img)}) @ $path');
            return;
          }
        }
      }
      // Fallback: dados antigos (bytes/base64/hex/data-uri)
      final anySig = widget.pedido['assinatura'] ??
          widget.pedido['assinatura_base64'] ??
          widget.pedido['signature'] ??
          widget.pedido['signature_base64'] ??
          widget.pedido['assinaturaBytes'];
      final img = signatureToImageBytes(anySig);
      if (img != null && img.isNotEmpty) {
        setState(() => _assinatura = img);
        // ignore: avoid_print
        print('[EDIT] assinatura carregada do campo (${img.length} bytes, tipo=${imageTypeFromBytes(img)})');
      } else {
        // ignore: avoid_print
        print('[EDIT] assinatura não encontrada (nem arquivo, nem campos)');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[EDIT] erro ao inicializar assinatura: $e');
    }
  }

  Future<void> _recarregarUltimoPedido() async {
    if (_clienteId == null) {
      setState(() => _ultimoPedido = null);
      return;
    }
    final last = await getUltimoPedidoCliente(_clienteId!);
    if (!mounted) return;
    setState(() => _ultimoPedido = last);
    // ignore: avoid_print
    print('[EDIT] ultimoPedido do cliente $_clienteId => ${_ultimoPedido?.toIso8601String()}');
  }

  Future<void> _carregarProdutos() async {
    setState(() => carregandoProdutos = true);
    // ignore: avoid_print
    print('[EDIT] carregando produtos...');
    final produtosDb = await buscarProdutosOnlineOuLocal();

    // prepara carrinho/quantidades com base no pedido existente
    _inicializarCarrinhoEControllers(produtosDb);

    if (!mounted) return;
    setState(() {
      produtos = produtosDb;
      carregandoProdutos = false;
    });
    // ignore: avoid_print
    print('[EDIT] produtos carregados: ${produtos.length}');
  }

  Future<void> _carregarClientes() async {
    final cli = await listarClientes();
    if (!mounted) return;
    setState(() => clientes = cli);
    // ignore: avoid_print
    print('[EDIT] clientes carregados: ${clientes.length}');
  }

  void _inicializarCarrinhoEControllers(List<Produto> produtosDb) {
    // itens do pedido podem vir como String (JSON) ou List
    final dynamic prodField = widget.pedido['produtos'];
    List itensPedido;
    if (prodField is String) {
      try {
        itensPedido = (jsonDecode(prodField) as List?) ?? <dynamic>[];
      } catch (_) {
        itensPedido = <dynamic>[];
      }
    } else if (prodField is List) {
      itensPedido = prodField;
    } else {
      itensPedido = <dynamic>[];
    }

    // limpa controllers antigos
    for (final c in _qtdControllers.values) {
      c.dispose();
    }
    _qtdControllers.clear();
    carrinho.clear();

    for (final p in produtosDb) {
      Map? salvo;
      for (final it in itensPedido) {
        if (it is Map && (it['nome'] ?? '') == p.nome) {
          salvo = it;
          break;
        }
      }
      final int qtd = (salvo?['quantidade'] is int)
          ? salvo!['quantidade'] as int
          : (int.tryParse('${salvo?['quantidade'] ?? '0'}') ?? 0);

      carrinho[p] = qtd;

      final ctrl = TextEditingController(text: qtd > 0 ? qtd.toString() : '');
      ctrl.addListener(() {
        final val = int.tryParse(ctrl.text) ?? 0;
        carrinho[p] = val < 0 ? 0 : val;
        setState(() {}); // atualiza total
      });
      _qtdControllers[p] = ctrl;
    }

    // ignore: avoid_print
    print('[EDIT] carrinho inicializado com ${produtosDb.length} produtos');
  }

  double get total =>
      carrinho.entries.fold(0.0, (s, e) => s + e.key.preco * (e.value));

  // ====== ASSINATURA: grava/atualiza arquivo e retorna caminho ======
  Future<String?> _persistirAssinaturaLocal(Uint8List? bytes,
      {required String numero}) async {
    if (bytes == null || bytes.isEmpty) {
      final old = widget.pedido['assinatura_path'];
      // ignore: avoid_print
      print('[EDIT] nenhuma nova assinatura; mantendo caminho antigo: ${old ?? 'null'}');
      return (old is String && old.isNotEmpty) ? old : null;
    }
    // se já existe um caminho, tenta sobrescrever
    final existing = widget.pedido['assinatura_path'];
    if (existing is String && existing.isNotEmpty) {
      try {
        final f = File(existing);
        await f.writeAsBytes(bytes, flush: true);
        // ignore: avoid_print
        print('[EDIT] assinatura sobrescrita (${bytes.length} bytes) em $existing');
        return existing;
      } catch (e) {
        // ignore: avoid_print
        print('[EDIT] falha ao sobrescrever assinatura em $existing: $e');
        // cai para criar novo
      }
    }
    // cria novo arquivo
    final dir = await getApplicationDocumentsDirectory();
    final sigDir = Directory('${dir.path}/signatures');
    if (!await sigDir.exists()) {
      await sigDir.create(recursive: true);
      // ignore: avoid_print
      print('[EDIT] diretório de assinaturas criado: ${sigDir.path}');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeNum =
    (numero.isEmpty ? 's_n' : numero).replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    final file = File('${sigDir.path}/sig_${safeNum}_$ts.png');
    await file.writeAsBytes(bytes, flush: true);
    // ignore: avoid_print
    print('[EDIT] assinatura gravada (${bytes.length} bytes) em ${file.path}');
    return file.path;
  }

  Future<void> _atualizarPedido({required String status}) async {
    if (processando) return;

    final itens = carrinho.entries
        .where((e) => e.value > 0)
        .map((e) => {
      'nome': e.key.nome,
      'preco': e.key.preco,
      'quantidade': e.value,
      'subtotal': (e.key.preco * e.value),
    })
        .toList();

    if (itens.isEmpty) {
      _showSnack('Adicione ao menos um produto ao pedido!');
      return;
    }
    if (status == 'finalizado' && (_assinatura == null || _assinatura!.isEmpty)) {
      _showSnack('É obrigatório assinar para finalizar!');
      return;
    }

    setState(() => processando = true);
    try {
      // garante persistência da assinatura como ARQUIVO
      final caminhoAss = await _persistirAssinaturaLocal(
        _assinatura,
        numero: numeroPedidoCtrl.text.trim(),
      );

      final pedidoAtualizado = {
        ...pedidoDaTela(
          base: widget.pedido,
          numero: numeroPedidoCtrl.text.trim(),
          produtos: itens,
          total: total,
          status: status,
          datahora: DateTime.now().toUtc().toIso8601String(),
          clienteId: _clienteId,
          cliente: {
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
          },
          // os bytes vão ao servidor (e ficam no SQLite para os reenvios);
          // o caminho fica só no aparelho
          assinatura: _assinatura,
          assinaturaPath: caminhoAss,
        ),
        // trocou o número que o servidor recusou: o conflito antigo não vale mais
        if (widget.pedido['erro_envio'] != null &&
            numeroPedidoCtrl.text.trim() != (widget.pedido['numero'] ?? '').toString().trim())
          'erro_envio': null,
      };

      // LOG
      // ignore: avoid_print
      print('[EDIT] atualizando pedido nº=${pedidoAtualizado['numero']} | status=$status total=$total | assinatura=${_assinatura == null ? 'null' : '${_assinatura!.length} bytes (tipo=${imageTypeFromBytes(_assinatura!)})'} | path=$caminhoAss');

      // Grava no aparelho na hora (nunca espera a rede) e, se finalizado, tenta
      // enviar. Um envio de pendentes que esteja no ar não sobrescreve esta
      // edição: o eco antigo é descartado em aplicarEcoDoServidor.
      final r = await gravarPedidoEEnviar(pedidoAtualizado, novo: false);

      if (!mounted) return;
      final msg = mensagemGravacao(r, status);
      if (msg != null) {
        _showSnack(msg, sucesso: !gravacaoEhAviso(r));
      }
      // ignore: avoid_print
      print('[EDIT] concluído ($r) -> pop("$status")');
      Navigator.pop(context, status);
    } on NumeroEmUso catch (e) {
      // Nada foi gravado: o formulário fica aberto para trocar o número.
      if (mounted) _showSnack(kMsgNumeroEmUso);
      // ignore: avoid_print
      print('[EDIT] $e');
    } catch (e) {
      if (mounted) _showSnack('Erro ao atualizar pedido.');
      // ignore: avoid_print
      print('[EDIT] erro ao atualizar pedido: $e');
    } finally {
      if (mounted) setState(() => processando = false);
    }
  }

  void _irParaAssinatura() async {
    if (processando) return;

    // LOG
    // ignore: avoid_print
    print('[EDIT] indo para tela de assinatura | atual=${_assinatura == null ? 0 : _assinatura!.length} bytes (${_assinatura == null ? 'null' : imageTypeFromBytes(_assinatura!)})');

    final dynamic ret = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssinaturaPage(assinatura: _assinatura)),
    );
    if (!mounted) return;

    // Aceita qualquer formato retornado e normaliza para imagem
    final img = signatureToImageBytes(ret);
    if (img != null && img.isNotEmpty) {
      setState(() => _assinatura = img);
      _showSnack('Assinatura salva!', sucesso: true);
      // ignore: avoid_print
      print('[EDIT] retorno da AssinaturaPage: ${ret.runtimeType}');
    } else {
      _showSnack('Falha ao obter a assinatura.');
      // ignore: avoid_print
      print('[EDIT] assinatura retornada inválida ou vazia.');
    }
  }

  // =========================
  // Busca/seleção de cliente por nome
  // =========================
  Future<void> _autoPreencherClientePorNome() async {
    await _carregarClientes();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final buscaCtrl = TextEditingController();
        List<Map<String, dynamic>> resultados = List.from(clientes);

        // LOG
        // ignore: avoid_print
        print('[EDIT] buscar cliente por nome');

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
        print('[EDIT] cliente selecionado => $_clienteId');
      }
    });
  }

  void _abrirPopupResumo() {
    // LOG
    // ignore: avoid_print
    print('[EDIT] abrir popup resumo');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                vendedor: (widget.pedido['vendedor_nome'] ?? '-').toString(),
                itens: [
                  for (final e in carrinho.entries.where((e) => e.value > 0))
                    (nome: e.key.nome, quantidade: e.value, subtotal: e.key.preco * e.value),
                ],
                total: total,
                assinatura: _assinatura,
                ocupado: processando,
                onAssinar: _irParaAssinatura,
                onSalvar: () {
                  Navigator.of(context).pop();
                  _atualizarPedido(status: 'salvo');
                },
                onFinalizar: () {
                  Navigator.of(context).pop();
                  _atualizarPedido(status: 'finalizado');
                },
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
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MdSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            readOnly: readOnly,
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
          if (label == 'Nome')
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

  void _showSnack(String msg, {bool sucesso = false}) {
    showMdSnack(context, msg, tipo: sucesso ? MdTipo.sucesso : MdTipo.erro);
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
    return Column(children: [left, right]);
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
    final mostrarForm = !carregandoProdutos && produtos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Pedido'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar produtos',
            onPressed: _carregarProdutos,
          ),
          const SizedBox(width: MdSpace.xs),
        ],
      ),
      bottomNavigationBar: mostrarForm && total > 0
          ? BarraResumo(
              total: total,
              onPressed: processando ? null : _abrirPopupResumo,
              ocupado: processando,
            )
          : null,
      body: carregandoProdutos
          ? const Center(child: CircularProgressIndicator())
          : produtos.isEmpty
              ? MdEmptyState(
                  icone: Icons.inventory_2_outlined,
                  titulo: 'Nenhum produto cadastrado.',
                  acao: FilledButton.icon(
                    onPressed: _carregarProdutos,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                )
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
                                  readOnly: !numeroEditavel(widget.pedido),
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

                        // Grade responsiva de produtos
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
                              habilitado: !processando,
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
