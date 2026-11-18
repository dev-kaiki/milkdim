// lib/pages/pedido_page.dart

import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/colors.dart';
import '../utils/produto.dart';
import '../utils/db.dart';
import '../utils/produto_service.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // <- signatureToImageBytes / assinaturaToBytes
import 'assinatura_page.dart' as assinatura; // alias para evitar ambiguidade

class PedidoPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;
  const PedidoPage({super.key, required this.vendedor});

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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
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
                        ? const Center(
                      child: Text('Nenhum cliente encontrado'),
                    )
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
        print('[PEDIDO] cliente selecionado => $_clienteId');
      }
    });
  }

  // ========================= Badge de recência =========================
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
  // ====================================================================

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
      final caminhoAss =
      await _gravarAssinaturaLocal(_assinatura, numero: numeroPedidoCtrl.text.trim());

      final pedido = {
        'numero': numeroPedidoCtrl.text.trim(),
        'produtos': produtosList,
        'total': total,
        'status': status,
        'datahora': DateTime.now().toUtc().toIso8601String(),
        'vendedor_codigo': widget.vendedor['codigo'],
        'vendedor_nome': widget.vendedor['nome'],

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

        // caminho local da assinatura
        'assinatura_path': caminhoAss,
      };

      // Sob a trava: não concorre com um envio de pendentes em andamento.
      await comTravaDePedidos(() async {
        // Salva local
        await salvarPedidoLocal(pedido);

        // Se finalizado, envia ao Supabase (e PRESERVA assinatura_path no SQLite)
        if (status == 'finalizado') {
          // 👇 Envie o pedido COMPLETO — o helper remove `assinatura_path` do payload do servidor
          // e depois regrava o mesmo valor no SQLite ao consolidar o retorno.
          // ignore: avoid_print
          print('[PEDIDO] enviando ao Supabase (preservando assinatura_path local) ...');
          await salvarPedidoSupabase(pedido);
        }
      });

      if (!mounted) return;
      // ignore: avoid_print
      print('[PEDIDO] concluído com sucesso -> pop("$status")');
      Navigator.pop(context, status);
    } catch (e) {
      _showMsg('Erro ao salvar pedido: $e');
      if (mounted) setState(() => carregando = false);
    }
  }

  void _abrirPopupResumo() {
    // ignore: avoid_print
    print('[PEDIDO] abrir popup de resumo');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: milkdimWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        final recencyText = _ultimoPedido == null
            ? 'Nunca'
            : DateFormat('dd/MM/yyyy HH:mm').format(_ultimoPedido!.toLocal());
        final recencyColor = _fgColor(_classify(_ultimoPedido));

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
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
                        fontSize: 22,
                        color: milkdimOrange,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _campoInfo('Nº Pedido:', numeroPedidoCtrl.text),
                  _campoInfo('Cliente:', nomeCtrl.text),
                  Row(
                    children: [
                      const Text('Último pedido:',
                          style: TextStyle(
                              color: milkdimDarkOrange,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text(recencyText,
                          style: TextStyle(
                              color: recencyColor, fontWeight: FontWeight.w700)),
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
                  _campoInfo('Vendedor:', widget.vendedor['nome'] ?? '-'),
                  const SizedBox(height: 8),

                  ...carrinho.entries
                      .where((e) => e.value > 0)
                      .map(
                        (e) => ListTile(
                      dense: true,
                      title: Text(
                        e.key.nome,
                        style: const TextStyle(
                            color: milkdimDarkOrange,
                            fontWeight: FontWeight.bold),
                      ),
                      trailing: Text(
                        'x${e.value}',
                        style: const TextStyle(
                            color: milkdimOrange,
                            fontWeight: FontWeight.bold),
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
                              fontSize: 18,
                              color: milkdimOrange,
                              fontWeight: FontWeight.bold)),
                      Text('R\$ ${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 18,
                              color: milkdimDarkOrange,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ===== Linha com assinatura + botão (com Flexible para evitar overflow) =====
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('Assinatura:',
                          style: TextStyle(
                              color: milkdimOrange,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: _assinatura == null
                            ? Container(
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: milkdimDarkOrange, width: 1.2),
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
                          child: Image.memory(
                            _assinatura!,
                            height: 50,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: carregando
                            ? null
                            : () async {
                          // PODE VOLTAR QUALQUER FORMATO -> convertemos
                          final dynamic assinaturaAny =
                          await Navigator.push(
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: milkdimOrange,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.edit,
                            color: milkdimWhite, size: 20),
                        label: const Text('Assinar',
                            style: TextStyle(color: milkdimWhite)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: carregando
                              ? null
                              : () {
                            Navigator.of(context).pop();
                            _salvarPedido('salvo');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: milkdimDarkOrange,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          icon:
                          const Icon(Icons.save, color: milkdimWhite),
                          label: carregando
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                              : const Text('Salvar',
                              style:
                              TextStyle(color: milkdimWhite)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: carregando
                              ? null
                              : () {
                            Navigator.of(context).pop();
                            _salvarPedido('finalizado');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: carregando
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                              : const Icon(Icons.check,
                              color: Colors.white),
                          label: const Text('Finalizar',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15)),
              labelStyle: const TextStyle(color: milkdimDarkOrange),
            ),
          ),
          if (isNome)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Último pedido',
                      style: TextStyle(
                          fontSize: 12, color: milkdimDarkOrange)),
                  _badgeUltimoPedido(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _campoInfo(String label, String valor) => Row(
    children: [
      Text(label,
          style: const TextStyle(
              color: milkdimDarkOrange, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          valor,
          style: TextStyle(
              color: valor.isEmpty ? Colors.red[400] : milkdimOrange,
              fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? milkdimDarkOrange : milkdimOrange,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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

    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        backgroundColor: milkdimWhite,
        elevation: 1,
        iconTheme: const IconThemeData(color: milkdimOrange),
        title: const Text(
          'Fazer Pedido',
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
      body: clientes.isEmpty || carregandoProdutos
          ? const Center(
        child: CircularProgressIndicator(color: milkdimOrange),
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

            // Grade de produtos
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: produtos.length,
              gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
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
                      style: const TextStyle(
                          color: milkdimDarkOrange, fontSize: 15),
                    ),
                    trailing: ConstrainedBox(
                      constraints:
                      const BoxConstraints(maxWidth: 90),
                      child: TextField(
                        controller: controller,
                        enabled: !carregando,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'Qtd',
                          labelStyle: const TextStyle(
                              fontSize: 12,
                              color: milkdimDarkOrange),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 3),
                        ),
                        onChanged: (value) {
                          final val = int.tryParse(value) ?? 0;
                          setState(() {
                            carrinho[p] = val < 0 ? 0 : val;
                          });
                        },
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
                  icon: const Icon(Icons.shopping_cart,
                      color: milkdimWhite),
                  label: Text(
                    'Resumo R\$ ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: milkdimWhite,
                        fontWeight: FontWeight.bold),
                  ),
                  onPressed: carregando ? null : _abrirPopupResumo,
                ),
              ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }
}

enum _RecencyLevel { none, green, orange, red }
