// lib/pages/pedido_edit_page.dart

import 'dart:convert'; // jsonDecode
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/colors.dart';
import '../utils/produto.dart';
import '../utils/produto_service.dart';
import '../utils/db.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // assinaturaToBytes / signatureToImageBytes / imageTypeFromBytes
import 'assinatura_page.dart' hide milkdimOrange, milkdimYellow;

class PedidoPageEdit extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const PedidoPageEdit({super.key, required this.pedido});

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
        ...widget.pedido,
        'numero': numeroPedidoCtrl.text.trim(),
        'produtos': itens,
        'total': total,
        'status': status,
        'datahora': DateTime.now().toUtc().toIso8601String(),

        // cliente
        'cliente_id': _clienteId,
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

        // somente o CAMINHO local:
        'assinatura_path': caminhoAss,
      };

      // LOG
      // ignore: avoid_print
      print('[EDIT] atualizando pedido nº=${pedidoAtualizado['numero']} | status=$status total=$total | assinatura=${_assinatura == null ? 'null' : '${_assinatura!.length} bytes (tipo=${imageTypeFromBytes(_assinatura!)})'} | path=$caminhoAss');

      // Grava no aparelho na hora (nunca espera a rede) e, se finalizado, tenta
      // enviar. Um envio de pendentes que esteja no ar não sobrescreve esta
      // edição: o eco antigo é descartado em aplicarEcoDoServidor.
      final r = await gravarPedidoEEnviar(pedidoAtualizado, novo: false);

      if (!mounted) return;
      if (r == ResultadoGravacao.pendente) {
        _showSnack('Pedido salvo. Será enviado quando houver internet.', sucesso: true);
      }
      // ignore: avoid_print
      print('[EDIT] concluído ($r) -> pop("$status")');
      Navigator.pop(context, status);
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Buscar cliente por nome'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: buscaCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => buscar(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 180,
                    width: 340,
                    child: resultados.isEmpty
                        ? const Center(child: Text('Nenhum cliente encontrado'))
                        : ListView.builder(
                      itemCount: resultados.length,
                      itemBuilder: (ctx, i) {
                        final cli = resultados[i];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(cli['nome'] ?? ''),
                          subtitle: Text(
                            (cli['cpf_cnpj'] ?? '') +
                                (cli['telefone'] != null
                                    ? " • ${cli['telefone']}"
                                    : ""),
                          ),
                          onTap: () {
                            Navigator.pop(context, cli);
                          },
                        );
                      },
                    ),
                  )
                ],
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: milkdimWhite,
      builder: (_) {
        final recencyText = _ultimoPedido == null
            ? 'Nunca'
            : DateFormat('dd/MM/yyyy HH:mm').format(_ultimoPedido!.toLocal());
        final recencyColor = _fgColor(_classify(_ultimoPedido));

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Resumo do Pedido',
                  style: TextStyle(
                      fontSize: 22, color: milkdimOrange, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _campoInfo('Nº Pedido:', numeroPedidoCtrl.text),
                _campoInfo('Cliente:', nomeCtrl.text),
                Row(
                  children: [
                    const Text('Último pedido:',
                        style: TextStyle(color: milkdimDarkOrange, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text(recencyText,
                        style: TextStyle(color: recencyColor, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                _campoInfo('Nome Fantasia:', nomeFantasiaCtrl.text),
                _campoInfo('Telefone:', telefoneCtrl.text),
                _campoInfo('WhatsApp:', whatsappCtrl.text),
                _campoInfo('Email:', emailCtrl.text),
                _campoInfo('Endereço:', enderecoCtrl.text),
                _campoInfo('Cidade:', cidadeCtrl.text),
                _campoInfo('CPF/CNPJ:', cpfCnpjCtrl.text),
                _campoInfo('Insc. Estadual:', inscEstadualCtrl.text),
                _campoInfo('CEP:', cepCtrl.text),
                _campoInfo('Anotação:', anotacaoCtrl.text),
                const SizedBox(height: 8),
                _campoInfo('Vendedor:', widget.pedido['vendedor_nome'] ?? '-'),
                const SizedBox(height: 10),

                // Lista de itens
                ...carrinho.entries.where((e) => e.value > 0).map(
                      (e) => ListTile(
                    dense: true,
                    title: Text(
                      e.key.nome,
                      style: const TextStyle(
                          color: milkdimDarkOrange, fontWeight: FontWeight.bold),
                    ),
                    trailing: Text(
                      'x${e.value}',
                      style: const TextStyle(
                          color: milkdimOrange, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'R\$ ${(e.key.preco * e.value).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                ),

                const Divider(height: 24, thickness: 1.5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:',
                        style: TextStyle(
                            fontSize: 18, color: milkdimOrange, fontWeight: FontWeight.bold)),
                    Text('R\$ ${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18, color: milkdimDarkOrange, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),

                // ======== ASSINATURA (sem overflow): Wrap + preview controlado ========
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text('Assinatura:',
                        style: TextStyle(color: milkdimOrange, fontWeight: FontWeight.w600)),
                    _assinatura == null
                        ? Container(
                      width: 200,
                      height: 70,
                      decoration: BoxDecoration(
                        border: Border.all(color: milkdimDarkOrange, width: 1.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('Não assinada',
                            style: TextStyle(
                                color: milkdimDarkOrange.withOpacity(0.7),
                                fontStyle: FontStyle.italic)),
                      ),
                    )
                        : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_assinatura!,
                          width: 200, height: 70, fit: BoxFit.contain),
                    ),
                    ElevatedButton.icon(
                      onPressed: processando ? null : _irParaAssinatura,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: milkdimOrange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.edit, color: milkdimWhite),
                      label: const Text('Assinar', style: TextStyle(color: milkdimWhite)),
                    ),
                  ],
                ),
                // =====================================================================

                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: processando
                            ? null
                            : () {
                          Navigator.of(context).pop();
                          _atualizarPedido(status: 'salvo');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: milkdimDarkOrange,
                          shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.save, color: milkdimWhite),
                        label: const Text('Salvar', style: TextStyle(color: milkdimWhite)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: processando
                            ? null
                            : () {
                          Navigator.of(context).pop();
                          _atualizarPedido(status: 'finalizado');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: processando
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                            : const Icon(Icons.check, color: Colors.white),
                        label: const Text('Finalizar', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // Badge de recência
  // =========================
  Widget _badgeUltimoPedido() {
    final level = _classify(_ultimoPedido);
    final fg = _fgColor(level);
    final bg = _bgColor(level);
    final label = _ultimoPedido == null
        ? 'Nunca'
        : DateFormat('dd/MM/yyyy').format(_ultimoPedido!.toLocal());

    IconData icon;
    switch (level) {
      case _RecencyLevel.green:
        icon = Icons.check_circle;
        break;
      case _RecencyLevel.orange:
        icon = Icons.schedule;
        break;
      case _RecencyLevel.red:
        icon = Icons.warning_amber_rounded;
        break;
      case _RecencyLevel.none:
        icon = Icons.do_not_disturb_on;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  _RecencyLevel _classify(DateTime? last) {
    if (last == null) return _RecencyLevel.none;
    final now = DateTime.now().toUtc();
    int days = now.difference(last.toUtc()).inDays;
    if (days < 0) days = 0;
    if (days < 15) return _RecencyLevel.green;
    if (days <= 30) return _RecencyLevel.orange;
    return _RecencyLevel.red;
  }

  Color _bgColor(_RecencyLevel l) {
    switch (l) {
      case _RecencyLevel.green:
        return Colors.green.shade600.withOpacity(0.12);
      case _RecencyLevel.orange:
        return Colors.amber.shade700.withOpacity(0.14);
      case _RecencyLevel.red:
        return Colors.red.shade700.withOpacity(0.14);
      case _RecencyLevel.none:
        return Colors.grey.shade600.withOpacity(0.15);
    }
  }

  Color _fgColor(_RecencyLevel l) {
    switch (l) {
      case _RecencyLevel.green:
        return Colors.green.shade700;
      case _RecencyLevel.orange:
        return Colors.amber.shade800;
      case _RecencyLevel.red:
        return Colors.red.shade700;
      case _RecencyLevel.none:
        return Colors.grey.shade600;
    }
  }
  // =========================

  Widget _campoCliente({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    VoidCallback? suffixIconTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: milkdimOrange),
              suffixIcon: suffixIconTap != null
                  ? IconButton(
                  icon: const Icon(Icons.search),
                  color: milkdimDarkOrange,
                  onPressed: suffixIconTap)
                  : null,
              labelText: label,
              fillColor: milkdimYellow.withOpacity(0.10),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              labelStyle: const TextStyle(color: milkdimDarkOrange),
            ),
          ),
          if (label == 'Nome')
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Último pedido',
                      style: TextStyle(fontSize: 12, color: milkdimDarkOrange)),
                  _badgeUltimoPedido(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget _campoInfo(String label, String valor) => Row(
    children: [
      Text(label,
          style:
          const TextStyle(color: milkdimDarkOrange, fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          valor,
          style: const TextStyle(color: milkdimOrange, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  void _showSnack(String msg, {bool sucesso = false}) {
    final snack = SnackBar(
      content: Text(msg),
      backgroundColor: sucesso ? milkdimOrange : milkdimDarkOrange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: Duration(seconds: sucesso ? 3 : 4),
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
  }

  // ---------- Helpers de layout responsivo ----------
  Widget _twoUp(bool horizontal, Widget left, Widget right) {
    if (horizontal) {
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
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

    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        backgroundColor: milkdimWhite,
        elevation: 1,
        iconTheme: const IconThemeData(color: milkdimOrange),
        title: const Text(
          'Editar Pedido',
          style: TextStyle(
            color: milkdimOrange,
            fontWeight: FontWeight.bold,
            fontSize: 24,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: milkdimDarkOrange),
            tooltip: 'Recarregar produtos',
            onPressed: _carregarProdutos,
          ),
        ],
      ),
      body: carregandoProdutos
          ? const Center(child: CircularProgressIndicator(color: milkdimOrange))
          : produtos.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Nenhum produto cadastrado.',
                style: TextStyle(color: milkdimDarkOrange)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _carregarProdutos,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(backgroundColor: milkdimOrange),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              color: milkdimWhite,
              margin: const EdgeInsets.only(bottom: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dados do Cliente',
                        style: TextStyle(
                            color: milkdimDarkOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 6),

                    _twoUp(
                      twoCols,
                      _campoCliente(
                        icon: Icons.numbers,
                        label: 'Nº Pedido',
                        controller: numeroPedidoCtrl,
                        keyboardType: TextInputType.number,
                      ),
                      _campoCliente(
                        icon: Icons.person,
                        label: 'Nome',
                        controller: nomeCtrl,
                        suffixIconTap: _autoPreencherClientePorNome,
                      ),
                    ),

                    _campoCliente(
                        icon: Icons.store,
                        label: 'Nome Fantasia',
                        controller: nomeFantasiaCtrl),

                    _twoUp(
                      twoCols,
                      _campoCliente(
                          icon: Icons.phone,
                          label: 'Telefone',
                          controller: telefoneCtrl,
                          keyboardType: TextInputType.phone),
                      _campoCliente(
                        icon: Icons.sms,
                        label: 'WhatsApp',
                        controller: whatsappCtrl,
                        keyboardType: TextInputType.phone,
                      ),
                    ),

                    _campoCliente(
                        icon: Icons.email,
                        label: 'Email',
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress),

                    _campoCliente(
                        icon: Icons.home,
                        label: 'Endereço',
                        controller: enderecoCtrl),

                    _twoUp(
                      twoCols,
                      _campoCliente(
                          icon: Icons.location_city,
                          label: 'Cidade',
                          controller: cidadeCtrl),
                      _campoCliente(
                          icon: Icons.map,
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
                          icon: Icons.assignment,
                          label: 'Insc. Estadual',
                          controller: inscEstadualCtrl),
                    ),

                    _campoCliente(
                        icon: Icons.edit,
                        label: 'Anotação',
                        controller: anotacaoCtrl,
                        maxLines: 2),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),
            const Text('Produtos',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: milkdimDarkOrange,
                    fontSize: 17)),
            const SizedBox(height: 4),

            // Grade responsiva de produtos
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: produtos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridCols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: gridCols == 1 ? 3.8 : 3.4,
              ),
              itemBuilder: (ctx, i) {
                final p = produtos[i];
                final controller = _qtdControllers[p]!;
                return Container(
                  decoration: BoxDecoration(
                    color: milkdimWhite,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: milkdimYellow.withOpacity(0.07),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: ListTile(
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(
                      p.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: milkdimOrange,
                          fontSize: 17),
                    ),
                    subtitle: Text(
                      'R\$ ${p.preco.toStringAsFixed(2)}',
                      style:
                      const TextStyle(color: milkdimDarkOrange, fontSize: 15),
                    ),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: TextField(
                        controller: controller,
                        enabled: !processando,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'Qtd',
                          labelStyle: const TextStyle(
                              fontSize: 12, color: milkdimDarkOrange),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 3),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
            if (total > 0)
              SizedBox(
                width: double.infinity,
                child: FloatingActionButton.extended(
                  elevation: 1,
                  backgroundColor: milkdimOrange,
                  icon: const Icon(Icons.shopping_cart, color: milkdimWhite),
                  label: Text(
                    'Resumo R\$ ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: milkdimWhite, fontWeight: FontWeight.bold),
                  ),
                  onPressed: processando ? null : _abrirPopupResumo,
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

enum _RecencyLevel { none, green, orange, red }
