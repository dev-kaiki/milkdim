// lib/pages/pedidos_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' as sq;

import '../utils/db.dart';
import '../utils/moeda.dart';
import '../utils/json_utils.dart';
import '../utils/pdf_utils.dart';
import '../utils/regras_pedido.dart';
import '../utils/supabase_helper.dart';
import '../utils/convert.dart'; // assinaturaToBytes / signatureToImageBytes

/// Recarregar sem servidor: a lista continua com o que está no aparelho.
const String kMsgSemServidorMeusPedidos =
    'Sem conexão com o servidor. Mostrando os pedidos do aparelho.';

Future<void> _baixarDoSupabase(String vendedorCodigo) =>
    sincronizarPedidos(vendedorCodigo: vendedorCodigo);

class PedidosPage extends StatefulWidget {
  /// Código do vendedor para filtrar os pedidos. Se null/vazio, mostra todos.
  final String? vendedorCodigo;

  /// Só para a captura visual: quando informado, mostra estes pedidos e não
  /// lê o SQLite ao abrir.
  final List<Map<String, dynamic>>? pedidosParaCaptura;

  /// Só para a captura visual: aba aberta (0 Em aberto, 1 Entregues, 2 Cancelados).
  final int abaInicialParaCaptura;

  /// Baixa do servidor os pedidos do vendedor (o que a fábrica mudou: pronto,
  /// finalizado manual, cancelado). Roda ao abrir e no Recarregar; nos testes,
  /// troca a chamada ao Supabase.
  final Future<void> Function(String vendedorCodigo) baixarPedidos;

  const PedidosPage({
    super.key,
    this.vendedorCodigo,
    this.pedidosParaCaptura,
    this.abaInicialParaCaptura = 0,
    this.baixarPedidos = _baixarDoSupabase,
  });

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage>
    with SingleTickerProviderStateMixin {
  bool _carregando = true;
  List<Map<String, dynamic>> _pedidos = [];

  // Busca livre
  final _buscaCtrl = TextEditingController();

  // ---- Filtros extras ----
  DateTimeRange? _range;
  String? _cidadeFiltro;
  String? _vendedorFiltro; // só usado quando não há filtro fixo por vendedor
  bool _somenteAssinados = false;
  final _minTotalCtrl = TextEditingController();
  final _maxTotalCtrl = TextEditingController();

  // Ordenação
  String _ordenacao =
      'data_desc'; // data_desc | data_asc | total_desc | total_asc | numero_desc | numero_asc

  @override
  void initState() {
    super.initState();
    final captura = widget.pedidosParaCaptura;
    if (captura != null) {
      _pedidos = captura;
      _carregando = false;
      if (widget.vendedorCodigo != null && widget.vendedorCodigo!.isNotEmpty) {
        _vendedorFiltro = widget.vendedorCodigo;
      }
      return;
    }
    _abrir();
  }

  /// Mostra logo o que está no aparelho e depois traz o servidor, sem aviso
  /// se não houver conexão.
  Future<void> _abrir() async {
    await _carregar();
    await _atualizarDoServidor(silencioso: true);
  }

  /// Baixa os pedidos do vendedor e relê o aparelho. Sem servidor, a lista
  /// fica como está (e avisa, se não for [silencioso]).
  Future<void> _atualizarDoServidor({bool silencioso = false}) async {
    final codigo = widget.vendedorCodigo;
    if (codigo == null || codigo.isEmpty) return _carregar();
    var ok = true;
    try {
      await widget.baixarPedidos(codigo);
    } catch (e) {
      ok = false;
      debugPrint('Meus pedidos: não deu para baixar do servidor: $e');
    }
    if (!mounted) return;
    await _carregar(mostrarCarregando: false);
    if (!ok && !silencioso && mounted) _snack(kMsgSemServidorMeusPedidos);
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    _minTotalCtrl.dispose();
    _maxTotalCtrl.dispose();
    super.dispose();
  }

  // ---------------- Utils assinatura ----------------
  /// Converte assinatura do pedido em bytes de IMAGEM (PNG/JPEG) para PDF/checagens.
  /// 1) Tenta arquivo local (`assinatura_path`)
  /// 2) Fallback para formatos antigos (base64/hex/data URI/Uint8List) nas chaves conhecidas
  Uint8List? _assinaturaAsBytes(Map<String, dynamic> pedido) {
    // 1) Caminho local (preferível)
    final dynamic pth = pedido['assinatura_path'];
    if (pth is String && pth.isNotEmpty) {
      try {
        // ✅ normaliza "file://...": evita falha ao abrir
        final path = pth.startsWith('file://') ? Uri.parse(pth).toFilePath() : pth;
        final f = File(path);
        if (f.existsSync()) {
          final bytes = f.readAsBytesSync();
          final img = signatureToImageBytes(bytes);
          if (img != null && img.isNotEmpty) return img;
        }
      } catch (_) {
        // ignora e tenta os formatos antigos
      }
    }

    // 2) Formatos antigos (bytes/base64/hex/data-uri)
    final dynamic any = pedido['assinatura'] ??
        pedido['assinatura_base64'] ??
        pedido['assinaturaBytes'] ??
        pedido['signature'] ??
        pedido['signature_base64'];

    final img = signatureToImageBytes(any);
    return (img != null && img.isNotEmpty) ? img : null;
  }

  /// Assinatura do pedido para o PDF: o arquivo do aparelho, senão os bytes
  /// (a sincronização limpa o caminho e traz os bytes do servidor).
  Uint8List? _assinaturaPedidoAsBytes(Map<String, dynamic> pedido) => imagemDaAssinatura(pedido,
      chaveBytes: 'assinatura_pedido', chaveCaminho: 'assinatura_pedido_path');

  // ---------------- Data ----------------

  Future<void> _carregar({bool mostrarCarregando = true}) async {
    if (mostrarCarregando) setState(() => _carregando = true);
    try {
      final db = await getDb();
      final hasFiltro =
      (widget.vendedorCodigo != null && widget.vendedorCodigo!.isNotEmpty);
      final rows = await db.query(
        'pedidos',
        where: hasFiltro ? 'vendedor_codigo = ?' : null,
        whereArgs: hasFiltro ? [widget.vendedorCodigo] : null,
        orderBy: 'datetime(datahora) DESC, id DESC',
      );
      if (!mounted) return;
      setState(() {
        _pedidos = rows;
        _carregando = false;
        if (hasFiltro) _vendedorFiltro = widget.vendedorCodigo;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _snack('Erro ao carregar pedidos: $e');
    }
  }

  Future<void> _apagarPedidoSalvo(Map<String, dynamic> pedido) async {
    final id = pedido['id'] as int?;
    if (id == null) return;

    // Apagado no Controle: o servidor não tem mais o pedido (a cópia ficou em
    // pedidos_descartados); só sai da lista do aparelho.
    final apagado = apagadoNoControle(pedido);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(apagado ? 'Apagar do aparelho?' : 'Apagar rascunho?'),
        content: Text(apagado
            ? 'Este pedido foi apagado no Controle e não será enviado. '
                'Deseja removê-lo do aparelho?'
            : 'Esse pedido ainda não foi finalizado. Deseja removê-lo do aparelho?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MdColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    final db = await getDb();
    final backup = Map<String, dynamic>.from(pedido);

    await db.delete('pedidos', where: 'id = ?', whereArgs: [id]);
    await _carregar();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(apagado ? 'Pedido apagado do aparelho.' : 'Rascunho apagado.'),
        action: SnackBarAction(
          label: 'DESFAZER',
          onPressed: () async {
            final db2 = await getDb();
            await db2.insert(
              'pedidos',
              backup,
              conflictAlgorithm: sq.ConflictAlgorithm.replace,
            );
            await _carregar();
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Botão do item: apaga rascunho antigo do aparelho ou cancela o pedido.
  Future<void> _remover(Map<String, dynamic> pedido) async {
    switch (acaoRemover(pedido)) {
      case AcaoRemover.apagarDoAparelho:
        return _apagarPedidoSalvo(pedido);
      case AcaoRemover.cancelar:
        return _cancelarPedido(pedido);
      case AcaoRemover.nenhuma:
        return;
    }
  }

  /// Pedido que o servidor recusou por número repetido (qualquer status): só o
  /// número muda, sem abrir a edição completa.
  Future<void> _trocarNumero(Map<String, dynamic> pedido) async {
    final vend = (pedido['vendedor_codigo'] ?? '').toString();
    final sugerido = await proximoNumeroLivreDoVendedor(vend);
    if (!mounted) return;
    final ctrl = TextEditingController(text: sugerido ?? '');
    String? erro;
    var conferindo = false;
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Trocar número'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Nº Pedido', errorText: erro),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: conferindo
                  ? null
                  : () async {
                      final n = ctrl.text.trim();
                      if (n.isEmpty) return;
                      setD(() => conferindo = true);
                      final livre = n != (pedido['numero'] ?? '').toString().trim() &&
                          await numeroLivreParaVendedor(n, vend);
                      if (!ctx.mounted) return;
                      if (livre) {
                        Navigator.pop(ctx, n);
                      } else {
                        setD(() {
                          conferindo = false;
                          erro = kMsgNumeroEmUso;
                        });
                      }
                    },
              child: const Text('Trocar número'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (novo == null) return;

    try {
      final status = (pedido['status'] ?? 'salvo').toString();
      final r = await gravarPedidoEEnviar(
        {...pedido, 'numero': novo, 'erro_envio': null, 'so_local': 0},
        novo: false,
      );
      await _carregar();
      if (!mounted) return;
      final msg = mensagemGravacao(r, status);
      _snack(msg ?? 'Número trocado.', ok: !gravacaoEhAviso(r));
    } on NumeroEmUso {
      if (mounted) _snack(kMsgNumeroEmUso);
    } catch (e) {
      // ignore: avoid_print
      print('[PEDIDOS] erro ao trocar número: $e');
      if (mounted) _snack('Erro ao trocar número.');
    }
  }

  Future<void> _cancelarPedido(Map<String, dynamic> pedido) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido?'),
        content: const Text('O pedido sai da produção e vai para a aba Cancelados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MdColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    try {
      final r = await gravarPedidoEEnviar(
        {...pedido, 'status': 'cancelado', 'so_local': 0},
        novo: false,
      );
      await _carregar();
      if (!mounted) return;
      switch (r) {
        case ResultadoGravacao.fechadoNoControle:
        case ResultadoGravacao.canceladoNoControle:
        case ResultadoGravacao.numeroEmUso:
        case ResultadoGravacao.apagadoNoControle:
        case ResultadoGravacao.pendente:
          _snack(mensagemGravacao(r, 'cancelado')!, ok: r == ResultadoGravacao.pendente);
        case ResultadoGravacao.enviado:
        case ResultadoGravacao.rascunho:
          _snack('Pedido cancelado.', ok: true);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[PEDIDOS] erro ao cancelar: $e');
      if (mounted) _snack('Erro ao cancelar pedido.');
    }
  }

  void _snack(String msg, {bool ok = false}) {
    showMdSnack(context, msg, tipo: ok ? MdTipo.sucesso : MdTipo.erro);
  }

  Future<void> _editar(Map<String, dynamic> pedido) async {
    final atualizado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PedidoPageEdit(pedido: pedido)),
    );
    if (atualizado != null) await _carregar();
  }

  // Pré-visualização (opcional)
  Future<void> _imprimirPdf(Map<String, dynamic> pedido) async {
    try {
      final assinatura = _assinaturaAsBytes(pedido); // bytes (ou null)
      final bytes = await gerarPdfPedido(
        pedido: pedido,
        assinaturaBytes: assinatura,
        assinaturaPedidoBytes: _assinaturaPedidoAsBytes(pedido),
      );
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      _snack('Falha ao abrir PDF: $e');
    }
  }

  Future<void> _compartilharPdf(Map<String, dynamic> pedido) async {
    try {
      final dir = await getTemporaryDirectory();
      final numero = (pedido['numero'] ?? 's_n').toString();
      final id = (pedido['id'] ?? '0').toString();
      final assinatura = _assinaturaAsBytes(pedido); // bytes (ou null)
      final pdfBytes = await gerarPdfPedido(
        pedido: pedido,
        assinaturaBytes: assinatura,
        assinaturaPedidoBytes: _assinaturaPedidoAsBytes(pedido),
      );
      final pdfFile = File('${dir.path}/pedido_${numero}_$id.pdf');
      await pdfFile.writeAsBytes(pdfBytes, flush: true);
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        text: 'Pedido #$numero (PDF)',
        subject: 'Pedido #$numero (PDF)',
      );
    } catch (e) {
      _snack('Falha ao compartilhar PDF: $e');
    }
  }

  Future<void> _compartilharJson(Map<String, dynamic> pedido) async {
    try {
      final dir = await getTemporaryDirectory();
      final numero = (pedido['numero'] ?? 's_n').toString();
      final id = (pedido['id'] ?? '0').toString();

      // Garante assinatura embutida no JSON em base64 sob a CHAVE ESPERADA: 'assinatura'
      final assinBytes = _assinaturaAsBytes(pedido);
      final pedidoParaExport = Map<String, dynamic>.from(pedido);
      if (assinBytes != null && assinBytes.isNotEmpty) {
        pedidoParaExport['assinatura'] = base64Encode(assinBytes);
      }

      final jsonStr = exportarPedidoParaJson(
        pedidoParaExport,
        pretty: true,
        incluirAssinatura: true,
        incluirId: true,
      );

      final jsonFile = File('${dir.path}/pedido_${numero}_$id.json');
      await jsonFile.writeAsString(jsonStr);
      await Share.shareXFiles(
        [XFile(jsonFile.path)],
        text: 'Pedido #$numero (JSON)',
        subject: 'Pedido #$numero (JSON)',
      );
    } catch (e) {
      _snack('Falha ao compartilhar JSON: $e');
    }
  }

  // ---------------- Filtro + Ordenação ----------------

  Iterable<String> _cidadesDisponiveis() sync* {
    final set = <String>{};
    for (final p in _pedidos) {
      final c = (p['cliente_cidade'] ?? '').toString().trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final v in list) yield v;
  }

  Iterable<String> _vendedoresDisponiveis() sync* {
    final set = <String>{};
    for (final p in _pedidos) {
      final c = (p['vendedor_codigo'] ?? '').toString().trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    for (final v in list) yield v;
  }

  bool _matchBuscaLivre(Map<String, dynamic> p, String q) {
    if (q.trim().isEmpty) return true;
    final tokens =
    q.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final blob = ([
      p['numero'],
      p['cliente_nome'],
      p['cliente_nome_fantasia'],
      p['cliente_cidade'],
      p['cliente_telefone'],
      p['cliente_email'],
      p['cliente_cpf_cnpj'],
      p['vendedor_nome'],
      p['vendedor_codigo'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()))
        .join(' ');

    for (final t in tokens) {
      if (!blob.contains(t)) return false;
    }
    return true;
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
  }

  DateTime? _asDate(dynamic v) {
    try {
      if (v == null) return null;
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  bool _passaFiltrosFixos(Map<String, dynamic> p) {
    // assinatura
    if (_somenteAssinados) {
      final asnBytes = _assinaturaAsBytes(p);
      if (asnBytes == null || asnBytes.isEmpty) return false;
    }
    // cidade
    if ((_cidadeFiltro ?? '').isNotEmpty) {
      final c = (p['cliente_cidade'] ?? '').toString();
      if (c != _cidadeFiltro) return false;
    }
    // vendedor (apenas quando não há filtro herdado via widget)
    if ((widget.vendedorCodigo == null ||
        widget.vendedorCodigo!.isNotEmpty == false) &&
        (_vendedorFiltro ?? '').isNotEmpty) {
      final v = (p['vendedor_codigo'] ?? '').toString();
      if (v != _vendedorFiltro) return false;
    }
    // total
    final minT = _lerValorDigitado(_minTotalCtrl.text);
    final maxT = _lerValorDigitado(_maxTotalCtrl.text);
    final t = _asDouble(p['total']);
    if (minT != null && t < minT) return false;
    if (maxT != null && t > maxT) return false;

    // intervalo de datas
    if (_range != null) {
      final dt = _asDate(p['datahora'])?.toLocal();
      if (dt == null) return false;
      final start =
      DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      if (dt.isBefore(start) || dt.isAfter(end)) return false;
    }
    return true;
  }

  int _cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_ordenacao) {
      case 'data_asc':
        return (_asDate(a['datahora']) ??
            DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(_asDate(b['datahora']) ??
            DateTime.fromMillisecondsSinceEpoch(0));
      case 'total_desc':
        return _asDouble(b['total']).compareTo(_asDouble(a['total']));
      case 'total_asc':
        return _asDouble(a['total']).compareTo(_asDouble(b['total']));
      case 'numero_desc':
        final an = int.tryParse((a['numero'] ?? '').toString()) ?? -1;
        final bn = int.tryParse((b['numero'] ?? '').toString()) ?? -1;
        return bn.compareTo(an);
      case 'numero_asc':
        final an2 = int.tryParse((a['numero'] ?? '').toString()) ?? -1;
        final bn2 = int.tryParse((b['numero'] ?? '').toString()) ?? -1;
        return an2.compareTo(bn2);
      case 'data_desc':
      default:
        return (_asDate(b['datahora']) ??
            DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(_asDate(a['datahora']) ??
            DateTime.fromMillisecondsSinceEpoch(0));
    }
  }

  // ---------- DEDUPE P/ FINALIZADOS (preferir com assinatura) ----------
  bool _temAssinatura(Map<String, dynamic> p) =>
      (_assinaturaAsBytes(p)?.isNotEmpty == true);

  String _chaveFinalizado(Map<String, dynamic> p) {
    final n = (p['numero'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    return 'id:${p['id']}';
  }

  Map<String, dynamic> _melhorRegistro(
      Map<String, dynamic>? atual, Map<String, dynamic> cand) {
    if (atual == null) return cand;

    final aAss = _temAssinatura(atual);
    final cAss = _temAssinatura(cand);
    if (aAss != cAss) return cAss ? cand : atual; // prefere assinados

    final adt =
        _asDate(atual['datahora']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cdt =
        _asDate(cand['datahora']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (cdt.isAfter(adt)) return cand;
    if (adt.isAfter(cdt)) return atual;

    final aid = (atual['id'] is int)
        ? (atual['id'] as int)
        : int.tryParse((atual['id'] ?? '0').toString()) ?? 0;
    final cid = (cand['id'] is int)
        ? (cand['id'] as int)
        : int.tryParse((cand['id'] ?? '0').toString()) ?? 0;
    return cid > aid ? cand : atual;
  }

  List<Map<String, dynamic>> _dedupFinalizados(
      List<Map<String, dynamic>> lista) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final p in lista) {
      final key = _chaveFinalizado(p);
      byKey[key] = _melhorRegistro(byKey[key], p);
    }
    return byKey.values.toList();
  }

  /// Pedidos da aba: 'salvo' é "Em aberto" (salvo e pronto, [estaEmAberto]);
  /// as outras abas filtram pela situação exata.
  List<Map<String, dynamic>> _filtrarPorStatus(String statusAlvo, String query) {
    final base = _pedidos.where(
      (p) => statusAlvo == 'salvo'
          ? estaEmAberto(p)
          : (p['status'] ?? '').toString().toLowerCase() == statusAlvo,
    );

    final listBase = statusAlvo == 'finalizado'
        ? _dedupFinalizados(base.toList())
        : base.toList();

    final filtrado = listBase
        .where((p) => _matchBuscaLivre(p, query) && _passaFiltrosFixos(p))
        .toList();

    filtrado.sort(_cmp);
    return filtrado;
  }

  // ---------------- UI helpers ----------------

  String _fmtData(dynamic v) {
    if (v == null) return '-';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  /// Aceita "1234.56", "1234,56" e "1.234,56" (como a tela mostra agora).
  double? _lerValorDigitado(String texto) {
    var t = texto.replaceAll('R\$', '').trim();
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  String _fmtTotal(dynamic v) {
    if (v is num) return formatarReais(v);
    final n = double.tryParse(v?.toString().replaceAll(',', '.') ?? '');
    return formatarReais(n ?? 0);
  }

  List _parseProdutos(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final d = jsonDecode(raw);
        return d is List ? d : const [];
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  int _countItens(List itens) {
    int s = 0;
    for (final it in itens) {
      final q = (it is Map ? it['quantidade'] : null);
      final n =
      (q is num) ? q.toInt() : int.tryParse(q?.toString() ?? '') ?? 0;
      s += (n < 0 ? 0 : n);
    }
    return s;
  }

  String _resumoProdutos(List itens, {int maxNames = 3}) {
    final nomes = <String>[];
    for (final it in itens) {
      if (it is Map) {
        final nome = (it['nome'] ?? '').toString();
        if (nome.isNotEmpty) nomes.add(nome);
      }
    }
    if (nomes.isEmpty) return 'Sem itens';
    if (nomes.length <= maxNames) return nomes.join(', ');
    final rest = nomes.length - maxNames;
    return '${nomes.take(maxNames).join(', ')} +$rest';
  }

  /// Selo de status do pedido: aberto, pronto ou finalizado ainda não enviado
  /// aparece como "Aguardando envio"; pronto para entrega, "Pronto";
  /// finalizado enviado, "Entregue"; em aberto, "Em aberto".
  Widget _seloStatus(Map<String, dynamic> p) {
    final status = (p['status'] ?? '-').toString();
    final pendente = (p['pendente_envio'] ?? 0).toString() == '1';
    if (apagadoNoControle(p)) {
      return const MdStatusChip(
          tipo: MdTipo.erro, texto: 'Apagado no Controle', icone: Icons.delete_outline);
    }
    if (p['erro_envio']?.toString() == kErroNumeroEmUso) {
      return const MdStatusChip(
          tipo: MdTipo.erro, texto: kMsgNumeroEmUso, icone: Icons.error_outline);
    }
    if ('${p['so_local'] ?? 0}' == '1') {
      return const MdStatusChip(
          tipo: MdTipo.atencao, texto: 'Não enviado', icone: Icons.cloud_off_outlined);
    }
    if (status == 'cancelado') {
      return const MdStatusChip(
          tipo: MdTipo.neutro, texto: 'Cancelado', icone: Icons.block);
    }
    if (estaEmAberto(p) && pendente) {
      return const MdStatusChip(
          tipo: MdTipo.atencao, texto: 'Aguardando envio', icone: Icons.cloud_upload_outlined);
    }
    if (estaPronto(p)) {
      return const MdStatusChip(
          tipo: MdTipo.sucesso, texto: 'Pronto', icone: Icons.local_shipping_outlined);
    }
    if (status == 'finalizado' && pendente) {
      return const MdStatusChip(
          tipo: MdTipo.atencao, texto: 'Aguardando envio', icone: Icons.cloud_upload_outlined);
    }
    if (status == 'finalizado') {
      return const MdStatusChip(
          tipo: MdTipo.sucesso, texto: 'Entregue', icone: Icons.check_circle_outline);
    }
    if (status == 'salvo') {
      return const MdStatusChip(
          tipo: MdTipo.neutro, texto: 'Em aberto', icone: Icons.edit_note);
    }
    return MdStatusChip(tipo: MdTipo.info, texto: status);
  }

  Widget _meta(IconData icone, String texto, TextStyle estilo) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 16, color: MdColors.textMuted),
      const SizedBox(width: MdSpace.xs),
      Flexible(child: Text(texto, style: estilo, overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _acao({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool principal = false,
    bool perigo = false,
  }) {
    const compacto = EdgeInsets.symmetric(horizontal: MdSpace.sm);
    if (principal) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(padding: compacto),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: perigo
          ? OutlinedButton.styleFrom(
              padding: compacto,
              foregroundColor: MdColors.danger,
              side: BorderSide(color: MdColors.danger.withValues(alpha: 0.5)),
            )
          : OutlinedButton.styleFrom(padding: compacto),
    );
  }

  // Card/item com pré-visualização mais rica
  Widget _pedidoTile(
      Map<String, dynamic> p, {
        required bool somenteLeitura,
      }) {
    final tt = Theme.of(context).textTheme;
    final numero = (p['numero'] ?? '-').toString();
    final cliente = (p['cliente_nome'] ?? '-').toString();
    final total = _fmtTotal(p['total']);
    final data = _fmtData(p['datahora']);
    final telefone = (p['cliente_telefone'] ?? '').toString();
    final cidade = (p['cliente_cidade'] ?? '').toString();
    final vendedor = (p['vendedor_nome'] ?? '').toString();
    final vendedorCod = (p['vendedor_codigo'] ?? '').toString();
    final cpfCnpj = (p['cliente_cpf_cnpj'] ?? '').toString();
    final temAssinatura = _temAssinatura(p);

    final itens = _parseProdutos(p['produtos']);
    final itensCount = _countItens(itens);
    final produtosResumo = _resumoProdutos(itens);

    final meta = tt.bodySmall!;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cliente,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium,
              ),
              const SizedBox(height: 2),
              Text('#$numero • $data', style: meta, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: MdSpace.sm),
        Text(
          total,
          style: tt.titleMedium!.copyWith(color: MdColors.primaryStrong),
        ),
      ],
    );

    final selos = Wrap(
      spacing: MdSpace.sm,
      runSpacing: MdSpace.sm,
      children: [
        _seloStatus(p),
        if (temAssinatura)
          const MdStatusChip(tipo: MdTipo.info, texto: 'Assinado', icone: Icons.draw_outlined),
        MdStatusChip(
          tipo: MdTipo.neutro,
          texto: '$itensCount iten${itensCount == 1 ? '' : 's'}',
          icone: Icons.shopping_bag_outlined,
        ),
      ],
    );

    final linhaCliente = Wrap(
      spacing: MdSpace.md,
      runSpacing: MdSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (telefone.isNotEmpty) _meta(Icons.call_outlined, telefone, meta),
        if (cidade.isNotEmpty) _meta(Icons.location_on_outlined, cidade, meta),
        if (cpfCnpj.isNotEmpty) _meta(Icons.credit_card, cpfCnpj, meta),
        if (vendedorCod.isNotEmpty)
          Tooltip(
            message: 'Vendedor $vendedor ($vendedorCod)',
            child: _meta(Icons.badge_outlined, vendedorCod, meta),
          ),
      ],
    );

    final produtosLinha = Text(
      produtosResumo,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: tt.bodyMedium,
    );

    // ações por status
    // Apagado no Controle: só "Apagar do aparelho" (sem editar, enviar,
    // trocar número nem registrar entrega).
    final apagado = apagadoNoControle(p);
    final acao = acaoRemover(p);
    final trocar = !apagado && podeTrocarNumero(p)
        ? _acao(
            label: 'Trocar número',
            icon: Icons.swap_horiz,
            onPressed: () => _trocarNumero(p),
          )
        : null;
    // Entregue pelo Controle sem a assinatura da entrega: o vendedor ainda
    // registra a entrega (a dele vale). O resto dos entregues é só leitura.
    final registrarEntrega = !apagado && podeRegistrarEntregaDepois(p)
        ? _acao(
            label: 'Registrar entrega',
            icon: Icons.local_shipping_outlined,
            onPressed: () => _editar(p),
            principal: true,
          )
        : null;
    final List<Widget> botoes = apagado
        ? [
            _acao(
              label: 'Apagar do aparelho',
              icon: Icons.delete_outline,
              onPressed: () => _remover(p),
              perigo: true,
            ),
          ]
        : somenteLeitura
        ? [
            _acao(
              label: 'Ver',
              icon: Icons.visibility_outlined,
              onPressed: () => _imprimirPdf(p),
            ),
            _acao(
              label: 'PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => _compartilharPdf(p),
            ),
            _acao(
              label: 'JSON',
              icon: Icons.data_object,
              onPressed: () => _compartilharJson(p),
            ),
          ]
        : [
            _acao(
              label: 'Editar',
              icon: Icons.edit_outlined,
              onPressed: () => _editar(p),
              principal: true,
            ),
            if (acao != AcaoRemover.nenhuma)
              _acao(
                label: acao == AcaoRemover.cancelar ? 'Cancelar pedido' : 'Apagar do aparelho',
                icon: acao == AcaoRemover.cancelar ? Icons.block : Icons.delete_outline,
                onPressed: () => _remover(p),
                perigo: true,
              ),
          ];

    final actions = Row(
      children: [
        for (var i = 0; i < botoes.length; i++) ...[
          if (i > 0) const SizedBox(width: MdSpace.sm),
          Expanded(child: botoes[i]),
        ],
      ],
    );

    return MdCard(
      onTap: apagado
          ? null
          : somenteLeitura
              ? () => _imprimirPdf(p)
              : () => _editar(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: MdSpace.md),
          selos,
          const SizedBox(height: MdSpace.md),
          produtosLinha,
          if (linhaCliente.children.isNotEmpty) ...[
            const SizedBox(height: MdSpace.sm),
            linhaCliente,
          ],
          const SizedBox(height: MdSpace.md),
          const Divider(),
          const SizedBox(height: MdSpace.md),
          if (trocar != null) ...[
            SizedBox(width: double.infinity, child: trocar),
            const SizedBox(height: MdSpace.sm),
          ],
          if (registrarEntrega != null) ...[
            SizedBox(width: double.infinity, child: registrarEntrega),
            const SizedBox(height: MdSpace.sm),
          ],
          actions,
        ],
      ),
    );
  }

  // ---- Abas ----
  Widget _aba(String status) {
    final query = _buscaCtrl.text;
    final lista = _filtrarPorStatus(status, query);
    // Em aberto (salvo e pronto) edita e cancela; entregues e cancelados só leitura.
    bool somenteLeitura(Map<String, dynamic> p) => !estaEmAberto(p);

    return RefreshIndicator(
      onRefresh: _atualizarDoServidor,
      child: LayoutBuilder(
        builder: (context, c) {
          if (_carregando) {
            return const Center(child: CircularProgressIndicator());
          }
          if (lista.isEmpty) {
            return MdEmptyState(
              icone: switch (status) {
                'finalizado' => Icons.receipt_long_outlined,
                'cancelado' => Icons.block,
                _ => Icons.edit_note,
              },
              titulo: switch (status) {
                'finalizado' => 'Nenhum pedido entregue.',
                'cancelado' => 'Nenhum pedido cancelado.',
                _ => 'Nenhum pedido em aberto.',
              },
            );
          }
          const pad = EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.sm, MdSpace.lg, MdSpace.lg);
          final colunas = (c.maxWidth / 520).floor().clamp(1, 3);
          if (colunas == 1) {
            return ListView.separated(
              padding: pad,
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: MdSpace.md),
              itemBuilder: (_, i) => _pedidoTile(lista[i], somenteLeitura: somenteLeitura(lista[i])),
            );
          }
          final largura =
              (c.maxWidth - pad.horizontal - MdSpace.md * (colunas - 1)) / colunas;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pad,
            child: Wrap(
              spacing: MdSpace.md,
              runSpacing: MdSpace.md,
              children: [
                for (final p in lista)
                  SizedBox(
                    width: largura,
                    child: _pedidoTile(p, somenteLeitura: somenteLeitura(p)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- UI filtros ativos (chips) ----
  Widget _chipsAtivos() {
    final chips = <Widget>[];

    if (_range != null) {
      final s = DateFormat('dd/MM').format(_range!.start);
      final e = DateFormat('dd/MM').format(_range!.end);
      chips.add(_chipAtivo('Período: $s–$e', () => setState(() => _range = null)));
    }
    if ((_cidadeFiltro ?? '').isNotEmpty) {
      chips.add(_chipAtivo('Cidade: $_cidadeFiltro',
              () => setState(() => _cidadeFiltro = null)));
    }
    if (_somenteAssinados) {
      chips.add(_chipAtivo('Somente assinados',
              () => setState(() => _somenteAssinados = false)));
    }
    final minT = _minTotalCtrl.text.trim();
    final maxT = _maxTotalCtrl.text.trim();
    if (minT.isNotEmpty || maxT.isNotEmpty) {
      chips.add(_chipAtivo(
          'Total: ${minT.isEmpty ? '0' : minT}–${maxT.isEmpty ? '∞' : maxT}', () {
        setState(() {
          _minTotalCtrl.clear();
          _maxTotalCtrl.clear();
        });
      }));
    }
    if ((widget.vendedorCodigo == null || widget.vendedorCodigo!.isEmpty) &&
        (_vendedorFiltro ?? '').isNotEmpty) {
      chips.add(_chipAtivo(
          'Vendedor: $_vendedorFiltro', () => setState(() => _vendedorFiltro = null)));
    }
    chips.add(_chipAtivo(_labelOrdenacao(_ordenacao), _alternarOrdenacao));

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: MdSpace.sm),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }

  String _labelOrdenacao(String key) {
    switch (key) {
      case 'data_asc':
        return 'Ordem: Data ↑';
      case 'total_desc':
        return 'Ordem: Total ↓';
      case 'total_asc':
        return 'Ordem: Total ↑';
      case 'numero_desc':
        return 'Ordem: Nº ↓';
      case 'numero_asc':
        return 'Ordem: Nº ↑';
      case 'data_desc':
      default:
        return 'Ordem: Data ↓';
    }
  }

  void _alternarOrdenacao() {
    const ordem = [
      'data_desc',
      'data_asc',
      'total_desc',
      'total_asc',
      'numero_desc',
      'numero_asc',
    ];
    final i = ordem.indexOf(_ordenacao);
    final prox = i == -1 ? 0 : (i + 1) % ordem.length;
    setState(() => _ordenacao = ordem[prox]);
  }

  Widget _chipAtivo(String label, VoidCallback onDeleted) => InputChip(
    label: Text(label),
    onDeleted: onDeleted,
    deleteIconColor: MdColors.textMuted,
  );

  // ---- BottomSheet de filtros ----
  void _abrirFiltros() async {
    final cidades = _cidadesDisponiveis().toList();
    final vendedores = _vendedoresDisponiveis().toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final minCtrl = TextEditingController(text: _minTotalCtrl.text);
        final maxCtrl = TextEditingController(text: _maxTotalCtrl.text);
        String? cidadeSel = _cidadeFiltro;
        String? vendSel = _vendedorFiltro;
        bool assinados = _somenteAssinados;
        DateTimeRange? range = _range;
        String ordem = _ordenacao;

        return Padding(
          padding: EdgeInsets.only(
            left: MdSpace.lg,
            right: MdSpace.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + MdSpace.lg,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              final tt = Theme.of(ctx).textTheme;
              Future<void> pickRange() async {
                final now = DateTime.now();
                final init = range ??
                    DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
                final r = await showDateRangePicker(
                  context: ctx,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(now.year + 1, 12, 31),
                  initialDateRange: init,
                );
                if (r != null) setModal(() => range = r);
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filtros', style: tt.titleLarge),
                    const SizedBox(height: MdSpace.md),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.date_range_outlined),
                      title: const Text('Período'),
                      subtitle: Text(
                        range == null
                            ? 'Qualquer data'
                            : '${DateFormat('dd/MM/yyyy').format(range!.start)} - ${DateFormat('dd/MM/yyyy').format(range!.end)}',
                      ),
                      onTap: pickRange,
                      trailing: range != null
                          ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setModal(() => range = null),
                      )
                          : null,
                    ),
                    const Divider(),
                    const SizedBox(height: MdSpace.md),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: cidadeSel?.isEmpty == true ? null : cidadeSel,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null, child: Text('Todas as cidades')),
                              ...cidades.map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c))),
                            ],
                            onChanged: (v) => setModal(() => cidadeSel = v),
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                          ),
                        ),
                        if (widget.vendedorCodigo == null ||
                            widget.vendedorCodigo!.isEmpty) ...[
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: vendSel?.isEmpty == true ? null : vendSel,
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem<String>(
                                    value: null, child: Text('Todos vendedores')),
                                ...vendedores.map((c) =>
                                    DropdownMenuItem(value: c, child: Text(c))),
                              ],
                              onChanged: (v) => setModal(() => vendSel = v),
                              decoration: const InputDecoration(
                                labelText: 'Vendedor',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: MdSpace.sm),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: assinados,
                      onChanged: (v) => setModal(() => assinados = v),
                      title: const Text('Somente pedidos assinados'),
                      secondary: const Icon(Icons.draw_outlined),
                    ),
                    const SizedBox(height: MdSpace.sm),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total mínimo',
                              prefixIcon: Icon(Icons.arrow_downward),
                            ),
                          ),
                        ),
                        const SizedBox(width: MdSpace.md),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total máximo',
                              prefixIcon: Icon(Icons.arrow_upward),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: MdSpace.lg),
                    Text('Ordenação', style: tt.titleSmall),
                    const SizedBox(height: MdSpace.sm),
                    Wrap(
                      spacing: MdSpace.sm,
                      runSpacing: MdSpace.sm,
                      children: [
                        for (final opt in const [
                          'data_desc',
                          'data_asc',
                          'total_desc',
                          'total_asc',
                          'numero_desc',
                          'numero_asc',
                        ])
                          ChoiceChip(
                            label: Text(_labelOrdenacao(opt)),
                            selected: ordem == opt,
                            onSelected: (_) => setModal(() => ordem = opt),
                          ),
                      ],
                    ),

                    const SizedBox(height: MdSpace.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _range = null;
                                _cidadeFiltro = null;
                                _somenteAssinados = false;
                                _minTotalCtrl.clear();
                                _maxTotalCtrl.clear();
                                if (widget.vendedorCodigo == null ||
                                    widget.vendedorCodigo!.isEmpty) {
                                  _vendedorFiltro = null;
                                }
                              });
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Limpar tudo'),
                          ),
                        ),
                        const SizedBox(width: MdSpace.md),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              setState(() {
                                _range = range;
                                _cidadeFiltro = cidadeSel;
                                _somenteAssinados = assinados;
                                _minTotalCtrl.text = minCtrl.text.trim();
                                _maxTotalCtrl.text = maxCtrl.text.trim();
                                if (widget.vendedorCodigo == null ||
                                    widget.vendedorCodigo!.isEmpty) {
                                  _vendedorFiltro = vendSel;
                                }
                                _ordenacao = ordem;
                              });
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MdSpace.sm),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final temFiltro =
    (widget.vendedorCodigo != null && widget.vendedorCodigo!.isNotEmpty);

    final finalizadosCount =
        _filtrarPorStatus('finalizado', _buscaCtrl.text).length;
    final abertosCount = _filtrarPorStatus('salvo', _buscaCtrl.text).length;
    final canceladosCount = _filtrarPorStatus('cancelado', _buscaCtrl.text).length;

    return DefaultTabController(
      length: 3,
      initialIndex: widget.abaInicialParaCaptura,
      child: Scaffold(
        appBar: AppBar(
          title: Text(temFiltro ? 'Meus Pedidos' : 'Pedidos'),
          actions: [
            IconButton(
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.tune),
              tooltip: 'Filtros',
            ),
            IconButton(
              onPressed: _atualizarDoServidor,
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar',
            ),
            const SizedBox(width: MdSpace.xs),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Em aberto ($abertosCount)'),
              Tab(text: 'Entregues ($finalizadosCount)'),
              Tab(text: 'Cancelados ($canceladosCount)'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Busca
            Padding(
              padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.md, MdSpace.lg, MdSpace.sm),
              child: MdSearchField(
                controller: _buscaCtrl,
                hint: 'Buscar cliente, nº, cidade, CPF/CNPJ…',
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Chips de filtros ativos
            _chipsAtivos(),
            const SizedBox(height: MdSpace.sm),

            Expanded(
              child: TabBarView(
                children: [
                  _aba('salvo'),
                  _aba('finalizado'),
                  _aba('cancelado'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
