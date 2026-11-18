// lib/pages/pedidos_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' as sq;

import '../utils/colors.dart';
import '../utils/db.dart';
import '../utils/json_utils.dart';
import '../utils/pdf_utils.dart';
import '../utils/convert.dart'; // assinaturaToBytes / signatureToImageBytes

class PedidosPage extends StatefulWidget {
  /// Código do vendedor para filtrar os pedidos. Se null/vazio, mostra todos.
  final String? vendedorCodigo;
  const PedidosPage({super.key, this.vendedorCodigo});

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
    _carregar();
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

  // ---------------- Data ----------------

  Future<void> _carregar() async {
    setState(() => _carregando = true);
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

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar rascunho?',
            style: TextStyle(color: milkdimDarkOrange)),
        content: const Text(
            'Esse pedido ainda não foi finalizado. Deseja removê-lo do aparelho?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
            const Text('Cancelar', style: TextStyle(color: milkdimDarkOrange)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
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
        content: const Text('Rascunho apagado.'),
        action: SnackBarAction(
          label: 'DESFAZER',
          textColor: milkdimWhite,
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
        backgroundColor: milkdimDarkOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? milkdimOrange : milkdimDarkOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
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
    final minT = double.tryParse(_minTotalCtrl.text.replaceAll(',', '.'));
    final maxT = double.tryParse(_maxTotalCtrl.text.replaceAll(',', '.'));
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

  List<Map<String, dynamic>> _filtrarPorStatus(String statusAlvo, String query) {
    final base = _pedidos.where(
          (p) => (p['status'] ?? '').toString().toLowerCase() == statusAlvo,
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

  String _fmtTotal(dynamic v) {
    if (v is num) return v.toStringAsFixed(2);
    final n = double.tryParse(v?.toString().replaceAll(',', '.') ?? '');
    return (n ?? 0).toStringAsFixed(2);
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

  Widget _pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }

  Widget _smallAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    Color? fg,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: fg ?? milkdimWhite,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        elevation: 1,
      ),
    );
  }

  // Card/item com pré-visualização mais rica
  Widget _pedidoTile(
      Map<String, dynamic> p, {
        required bool compacto,
        required bool isFinalizado,
      }) {
    final numero = (p['numero'] ?? '-').toString();
    final cliente = (p['cliente_nome'] ?? '-').toString();
    final status = (p['status'] ?? '-').toString();
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

    final Color badgeColor =
    status == 'finalizado' ? Colors.green : milkdimDarkOrange;

    final header = Row(
      children: [
        Expanded(
          child: Text(
            cliente,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: milkdimOrange,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: .2,
            ),
          ),
        ),
        if (temAssinatura) ...[
          _pill('ASSINADO', Colors.teal, icon: Icons.draw_rounded),
          const SizedBox(width: 8),
        ],
        _pill(status.toUpperCase(), badgeColor),
      ],
    );

    final metaTop = Row(
      children: [
        Expanded(
          child: Text(
            '#$numero • $data',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Vendedor $vendedor ($vendedorCod)',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.badge_outlined, size: 14, color: Colors.black54),
              const SizedBox(width: 4),
              Text(
                vendedorCod,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );

    final linhaCliente = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (telefone.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.call_outlined, size: 14, color: Colors.black54),
            const SizedBox(width: 4),
            Text(telefone, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        if (cidade.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on_outlined, size: 14, color: Colors.black54),
            const SizedBox(width: 4),
            Text(cidade, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        if (cpfCnpj.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.credit_card, size: 14, color: Colors.black54),
            const SizedBox(width: 4),
            Text(cpfCnpj, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
      ],
    );

    final produtosLinha = Row(
      children: [
        Expanded(
          child: Text(
            produtosResumo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 8),
        _pill('$itensCount iten${itensCount == 1 ? '' : 's'}',
            milkdimDarkOrange,
            icon: Icons.shopping_bag_outlined),
      ],
    );

    final totalBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: milkdimYellow.withOpacity(0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'R\$ $total',
        style: const TextStyle(
          color: milkdimDarkOrange,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: .2,
        ),
      ),
    );

    // ações por status
    Widget actions;
    if (isFinalizado) {
      actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _smallAction(
            label: 'Ver',
            icon: Icons.visibility_outlined,
            onPressed: () => _imprimirPdf(p),
            color: Colors.blueGrey,
          ),
          _smallAction(
            label: 'PDF',
            icon: Icons.picture_as_pdf,
            onPressed: () => _compartilharPdf(p),
            color: milkdimDarkOrange,
          ),
          _smallAction(
            label: 'JSON',
            icon: Icons.data_object,
            onPressed: () => _compartilharJson(p),
            color: milkdimOrange,
          ),
        ],
      );
    } else {
      actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _smallAction(
            label: 'Editar',
            icon: Icons.edit,
            onPressed: () => _editar(p),
            color: milkdimDarkOrange,
          ),
          _smallAction(
            label: 'Apagar',
            icon: Icons.delete_outline,
            onPressed: () => _apagarPedidoSalvo(p),
            color: Colors.redAccent,
          ),
        ],
      );
    }

    final contentCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 6),
        metaTop,
        const SizedBox(height: 6),
        linhaCliente,
        const SizedBox(height: 8),
        produtosLinha,
        const SizedBox(height: 12),
        Row(
          children: [
            totalBox,
            const Spacer(),
            actions,
          ],
        ),
      ],
    );

    final cardChild = compacto
        ? contentCol
        : Row(children: [Expanded(flex: 3, child: contentCol)]);

    return Material(
      color: milkdimWhite,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isFinalizado ? () => _imprimirPdf(p) : () => _editar(p),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: milkdimYellow.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              )
            ],
            border: Border.all(color: milkdimYellow.withOpacity(0.20)),
          ),
          child: cardChild,
        ),
      ),
    );
  }

  Widget _emptyState(String titulo, {VoidCallback? onReload}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: milkdimYellow.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox, size: 40, color: milkdimDarkOrange),
          ),
          const SizedBox(height: 12),
          Text(titulo,
              style: const TextStyle(
                  color: milkdimDarkOrange, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (onReload != null)
            FilledButton.tonalIcon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Recarregar'),
              style: FilledButton.styleFrom(
                foregroundColor: milkdimDarkOrange,
                backgroundColor: milkdimYellow.withOpacity(0.25),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Abas ----
  Widget _aba(String status) {
    final query = _buscaCtrl.text;
    final lista = _filtrarPorStatus(status, query);
    final isFinalizado = status == 'finalizado';

    return RefreshIndicator(
      color: milkdimOrange,
      onRefresh: _carregar,
      child: LayoutBuilder(
        builder: (context, c) {
          final isCompact = c.maxWidth < 720;
          if (_carregando) {
            return const Center(
                child: CircularProgressIndicator(color: milkdimOrange));
          }
          if (lista.isEmpty) {
            return _emptyState(isFinalizado
                ? 'Nenhum pedido finalizado.'
                : 'Nenhum rascunho salvo.');
          }
          if (isCompact) {
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _pedidoTile(lista[i],
                  compacto: true, isFinalizado: isFinalizado),
            );
          } else {
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 720,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
              itemCount: lista.length,
              itemBuilder: (_, i) => _pedidoTile(lista[i],
                  compacto: false, isFinalizado: isFinalizado),
            );
          }
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
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
    deleteIconColor: milkdimDarkOrange,
    backgroundColor: milkdimYellow.withOpacity(0.18),
    labelStyle: const TextStyle(color: milkdimDarkOrange),
  );

  // ---- BottomSheet de filtros ----
  void _abrirFiltros() async {
    final cidades = _cidadesDisponiveis().toList();
    final vendedores = _vendedoresDisponiveis().toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: milkdimWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: milkdimYellow,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const Text('Filtros',
                        style: TextStyle(
                            color: milkdimDarkOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    const SizedBox(height: 12),

                    ListTile(
                      leading: const Icon(Icons.date_range, color: milkdimDarkOrange),
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

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: cidadeSel?.isEmpty == true ? null : cidadeSel,
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
                        const SizedBox(width: 10),
                        if (widget.vendedorCodigo == null ||
                            widget.vendedorCodigo!.isEmpty)
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: vendSel?.isEmpty == true ? null : vendSel,
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
                    ),
                    const SizedBox(height: 10),

                    SwitchListTile(
                      value: assinados,
                      onChanged: (v) => setModal(() => assinados = v),
                      title: const Text('Somente pedidos assinados'),
                      secondary:
                      const Icon(Icons.draw_rounded, color: milkdimDarkOrange),
                    ),
                    const SizedBox(height: 6),

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
                        const SizedBox(width: 10),
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

                    const SizedBox(height: 12),
                    const Text('Ordenação',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: milkdimDarkOrange)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton.icon(
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
                        const Spacer(),
                        FilledButton.icon(
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
                          style: FilledButton.styleFrom(
                              backgroundColor: milkdimDarkOrange),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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
    final salvosCount = _filtrarPorStatus('salvo', _buscaCtrl.text).length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: milkdimWhite,
        appBar: AppBar(
          backgroundColor: milkdimWhite,
          elevation: 1,
          iconTheme: const IconThemeData(color: milkdimOrange),
          title: Text(
            temFiltro ? 'Meus Pedidos' : 'Pedidos',
            style: const TextStyle(
              color: milkdimOrange,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.filter_list, color: milkdimDarkOrange),
              tooltip: 'Filtros',
            ),
            IconButton(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh, color: milkdimDarkOrange),
              tooltip: 'Recarregar',
            ),
          ],
          bottom: TabBar(
            indicatorColor: milkdimOrange,
            labelColor: milkdimOrange,
            unselectedLabelColor: milkdimDarkOrange,
            tabs: [
              Tab(text: 'Finalizados ($finalizadosCount)'),
              Tab(text: 'Salvos ($salvosCount)'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Busca
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _buscaCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                  'Buscar por cliente, nº, cidade, CPF/CNPJ, vendedor...',
                  prefixIcon:
                  const Icon(Icons.search, color: milkdimDarkOrange),
                  suffixIcon: _buscaCtrl.text.isEmpty
                      ? null
                      : IconButton(
                    icon: const Icon(Icons.clear,
                        color: milkdimDarkOrange),
                    onPressed: () {
                      _buscaCtrl.clear();
                      setState(() {});
                    },
                  ),
                  filled: true,
                  fillColor: milkdimYellow.withOpacity(0.10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 0),
                ),
              ),
            ),

            // Chips de filtros ativos
            _chipsAtivos(),
            const SizedBox(height: 6),

            Expanded(
              child: TabBarView(
                children: [
                  _aba('finalizado'),
                  _aba('salvo'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
