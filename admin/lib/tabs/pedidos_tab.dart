// lib/tabs/pedidos_tab.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pedido.dart';

final supabase = Supabase.instance.client;

/// Lista de pedidos; ao tocar, abre detalhes formatados (usando `Pedido`)
/// e também mostra um bloco com **todas as colunas** (JSON bruto).
class PedidosTab extends StatefulWidget {
  const PedidosTab({super.key});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab> {
  final _searchCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd/MM HH:mm');

  bool _loading = true;
  List<Pedido> _pedidos = [];
  List<Pedido> _filtered = [];

  @override
  void initState() {
    super.initState();
    _fetchPedidos();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------- DATA (lista) --------------------

  Future<void> _fetchPedidos() async {
    setState(() => _loading = true);
    try {
      // Colunas reais (sem aliases); o modelo `Pedido` espera snake_case.
      final rows = await supabase
          .from('pedidos')
          .select(
        'id, cliente_id, cliente_nome, cliente_nome_fantasia, '
            'cliente_cidade, cliente_telefone, cliente_whatsapp, cliente_email, cliente_cpf_cnpj, '
            'status, datahora, total, vendedor_codigo, vendedor_nome, '
            'numero, produtos',
      )
          .order('datahora', ascending: false);

      final list = (rows as List)
          .map((m) => Pedido.fromMap(m as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _pedidos = list;
        _filtered = list;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar pedidos: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- DELETE --------------------

  /// Abre o diálogo de confirmação e, se confirmado, apaga o pedido.
  /// Retorna true se apagou com sucesso.
  Future<bool> _confirmDelete(Pedido p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar pedido #${p.id}?'),
        content: const Text(
          'Esta ação não pode ser desfeita. Deseja realmente apagar este pedido?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    return await _deletePedidoById(p.id);
  }

  /// Executa o DELETE no Supabase e atualiza as listas locais.
  Future<bool> _deletePedidoById(int id) async {
    try {
      await supabase.from('pedidos').delete().eq('id', id);

      if (!mounted) return true; // já apagou no servidor
      setState(() {
        _pedidos.removeWhere((x) => x.id == id);
        _filtered.removeWhere((x) => x.id == id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido #$id apagado com sucesso.')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao apagar pedido #$id: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
      return false;
    }
  }

  // -------------------- DATA (detalhes) --------------------

  /// Busca 1) linha crua do Supabase (todas as colunas) e
  /// 2) mapeia para `Pedido` para renderização bonita.
  Future<({Map<String, dynamic> raw, Pedido parsed})?> _fetchPedidoDetalhe(int id) async {
    try {
      final raw = await supabase.from('pedidos').select('*').eq('id', id).single();
      final map = Map<String, dynamic>.from(raw as Map);
      final parsed = Pedido.fromMap(map);
      return (raw: map, parsed: parsed);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar detalhes do pedido #$id: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
      return null;
    }
  }

  // -------------------- SEARCH --------------------

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List.of(_pedidos));
      return;
    }
    setState(() {
      _filtered = _pedidos.where((p) {
        String s(Object? x) => (x ?? '').toString().toLowerCase();
        return s(p.clienteNome).contains(q) ||
            s(p.clienteNomeFantasia).contains(q) ||
            p.status.toLowerCase().contains(q) ||
            s(p.numero).contains(q) ||
            p.id.toString().contains(q) ||
            s(p.vendedorCodigo).contains(q) ||
            s(p.vendedorNome).contains(q) ||
            s(p.clienteCidade).contains(q) ||
            s(p.clienteTelefone).contains(q) ||
            s(p.clienteWhatsapp).contains(q) ||
            s(p.clienteEmail).contains(q) ||
            s(p.clienteCpfCnpj).contains(q) ||
            _produtosResumo(p.itens).toLowerCase().contains(q);
      }).toList();
    });
  }

  // -------------------- HELPERS --------------------

  String _fmtData(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '-';
    return _dateFmt.format(dt.toLocal());
  }

  String _fmtMoeda(num? v) {
    if (v == null) return 'R\$ 0,00';
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $s';
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('final')) return const Color(0xFF2E7D32); // verde
    if (s.contains('cancel')) return const Color(0xFFC62828); // vermelho
    if (s.contains('pend') || s.contains('aguard')) return const Color(0xFFF9A825); // amarelo
    return const Color(0xFF546E7A); // cinza azulado (default)
  }

  Chip _statusChip(String status) => Chip(
    label: Text(status),
    labelStyle: const TextStyle(color: Colors.white),
    backgroundColor: _statusColor(status),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  String _maybeJoin(List<String?> parts) {
    final filt = parts.where((e) => e != null && e!.trim().isNotEmpty).cast<String>().toList();
    return filt.isEmpty ? '—' : filt.join(' · ');
  }

  String _produtosResumo(List<PedidoItem> itens, {int maxNames = 3}) {
    final nomes = <String>[];
    for (final it in itens) {
      if (it.nome.trim().isNotEmpty) nomes.add(it.nome.trim());
    }
    if (nomes.isEmpty) return 'Sem itens';
    if (nomes.length <= maxNames) return nomes.join(', ');
    final rest = nomes.length - maxNames;
    return '${nomes.take(maxNames).join(', ')} +$rest';
  }

  Future<void> _copy(String label, String? value) async {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // Mostra um rótulo + valor, aceitando qualquer tipo.
  // Se for Map/List, mostra um bloco JSON identado e selecionável.
  Widget _infoRow(String label, Object? value, {bool dense = false}) {
    String v;
    bool isJsonBlock = false;

    if (value == null) {
      v = '—';
    } else if (value is String) {
      v = value.trim().isEmpty ? '—' : value;
    } else if (value is bool) {
      v = value ? 'Sim' : 'Não';
    } else if (value is num) {
      v = value.toString();
    } else if (value is DateTime) {
      v = _dateFmt.format(value.toLocal());
    } else if (value is Map || value is Iterable) {
      v = const JsonEncoder.withIndent('  ').convert(value);
      isJsonBlock = true;
    } else {
      v = value.toString();
    }

    Widget valueWidget;
    if (isJsonBlock) {
      valueWidget = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.black.withOpacity(0.04),
        ),
        padding: const EdgeInsets.all(10),
        child: SelectableText(
          v,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.25),
        ),
      );
    } else {
      valueWidget = Text(v);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  // (Opcional) quando quiser renderizar um widget no valor:
  Widget infoRowWidget(String label, Widget value, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: value),
        ],
      ),
    );
  }

  // -------------------- UI --------------------

  void _openDetalhesPedido(Pedido pFromList) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FutureBuilder<({Map<String, dynamic> raw, Pedido parsed})?>(
              future: _fetchPedidoDetalhe(pFromList.id),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snap.data;
                if (data == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Não foi possível carregar os detalhes.'),
                  );
                }

                final raw = data.raw;
                final ped = data.parsed;
                final jsonStr = const JsonEncoder.withIndent('  ').convert(raw);

                return DraggableScrollableSheet(
                  expand: false,
                  minChildSize: 0.25,
                  initialChildSize: 0.9,
                  maxChildSize: 0.95,
                  builder: (context, controller) {
                    final clienteTitulo =
                    (ped.clienteNome ?? ped.clienteNomeFantasia ?? 'Cliente').toString();
                    return ListView(
                      controller: controller,
                      children: [
                        // HEADER
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                clienteTitulo,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if ((ped.numero ?? '').isNotEmpty)
                              Chip(label: Text('Nº ${ped.numero}')),
                            const SizedBox(width: 8),
                            Chip(label: Text('ID ${ped.id}')),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Apagar pedido',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final deleted = await _confirmDelete(ped);
                                if (deleted && mounted) {
                                  Navigator.of(context).pop(); // fecha a folha de detalhes
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _statusChip(ped.status),
                            Chip(label: Text('Total: ${_fmtMoeda(ped.total)}')),
                            Chip(label: Text('Itens: ${ped.totalItens}')),
                            if ((ped.vendedorCodigo ?? '').isNotEmpty ||
                                (ped.vendedorNome ?? '').isNotEmpty)
                              Chip(
                                avatar: const Icon(Icons.badge_outlined, size: 18),
                                label: Text(
                                  (ped.vendedorCodigo ?? '') +
                                      ((ped.vendedorNome ?? '').isNotEmpty
                                          ? ' (${ped.vendedorNome})'
                                          : ''),
                                ),
                              ),
                            Chip(label: Text('Quando: ${_fmtData(ped.datahora)}')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(),

                        // ITENS
                        const SizedBox(height: 12),
                        const Text('Itens do pedido',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(
                                label: Text('Produto',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              DataColumn(label: Text('Preço')),
                              DataColumn(label: Text('Qtd')),
                              DataColumn(label: Text('Subtotal')),
                            ],
                            rows: ped.itens
                                .map(
                                  (it) => DataRow(
                                cells: [
                                  DataCell(Text(it.nome)),
                                  DataCell(Text(_fmtMoeda(it.preco))),
                                  DataCell(Text(it.quantidade.toString())),
                                  DataCell(Text(_fmtMoeda(it.subtotal))),
                                ],
                              ),
                            )
                                .toList(),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8, right: 4),
                            child: Text(
                              'Total: ${_fmtMoeda(ped.total)}',
                              style:
                              const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                        ),

                        // CLIENTE
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text('Dados do cliente',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _infoRow('Código (ID)', ped.clienteId, dense: true),
                        _infoRow('Nome', ped.clienteNome, dense: true),
                        _infoRow('Nome fantasia', ped.clienteNomeFantasia, dense: true),
                        infoRowWidget(
                          'Telefone/WhatsApp',
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if ((ped.clienteTelefone ?? '').trim().isNotEmpty)
                              ActionChip(
                                avatar: const Icon(Icons.call_outlined, size: 18),
                                label: Text(ped.clienteTelefone!),
                                onPressed: () => _copy('Telefone', ped.clienteTelefone),
                              ),
                            if ((ped.clienteWhatsapp ?? '').trim().isNotEmpty)
                              ActionChip(
                                avatar: const Icon(Icons.sms, size: 18),
                                label: Text(ped.clienteWhatsapp!),
                                onPressed: () => _copy('WhatsApp', ped.clienteWhatsapp),
                              ),
                          ]),
                          dense: true,
                        ),
                        _infoRow('Email', ped.clienteEmail, dense: true),
                        _infoRow('Endereço', ped.clienteEndereco, dense: true),
                        _infoRow('Cidade', ped.clienteCidade, dense: true),
                        _infoRow('CPF/CNPJ', ped.clienteCpfCnpj, dense: true),
                        _infoRow('Inscr. Estadual', ped.clienteInscEstadual, dense: true),
                        _infoRow('CEP', ped.clienteCep, dense: true),
                        _infoRow('Anotação', ped.clienteAnotacao),

                        // VENDEDOR
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text('Vendedor',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _infoRow('Código', ped.vendedorCodigo),
                        _infoRow('Nome', ped.vendedorNome),

                        // DADOS BRUTOS / TODAS AS COLUNAS
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Dados brutos (todas as colunas)',
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            IconButton(
                              tooltip: 'Copiar JSON',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: jsonStr));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'JSON copiado para a área de transferência.')),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.black.withOpacity(0.04),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            jsonStr,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // -------------------- UI (lista com pré-visualização rica) --------------------

  @override
  Widget build(BuildContext context) {
    final small =
    Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54, height: 1.15);

    return Column(
      children: [
        // 🔎 busca
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText:
              'Buscar por cliente, status, número, ID, cidade, contato, CPF/CNPJ, produto…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),

        // 🔄 atualizar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _loading ? null : _fetchPedidos,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
              const SizedBox(width: 12),
              if (_loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),

        // 📋 lista
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
            onRefresh: _fetchPedidos,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _filtered[i];
                final cliente =
                (p.clienteNome ?? p.clienteNomeFantasia ?? '—').toString();
                final status = p.status;
                final numero = (p.numero ?? '').toString();
                final cidade = p.clienteCidade;
                final contatos =
                _maybeJoin([p.clienteTelefone, p.clienteWhatsapp, p.clienteEmail]);
                final cpfcnpj =
                (p.clienteCpfCnpj ?? '').trim().isEmpty ? null : p.clienteCpfCnpj;
                final resumo = _produtosResumo(p.itens);

                return Card(
                  elevation: 1,
                  shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openDetalhesPedido(p),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: _statusColor(status), width: 4),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _statusColor(status).withOpacity(.12),
                            child: Text(
                                (cliente.isNotEmpty ? cliente[0] : '?').toUpperCase()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Linha 1: nome do cliente
                                Text(
                                  cliente,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Linha 2: chips principais
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _statusChip(status),
                                    if (numero.isNotEmpty)
                                      Chip(label: Text('Nº $numero')),
                                    Chip(label: Text('Itens: ${p.totalItens}')),
                                    Chip(label: Text(_fmtData(p.datahora))),
                                    if ((p.vendedorCodigo ?? '').isNotEmpty ||
                                        (p.vendedorNome ?? '').isNotEmpty)
                                      Chip(
                                        avatar: const Icon(Icons.badge_outlined, size: 18),
                                        label: Text(
                                          (p.vendedorCodigo ?? '') +
                                              ((p.vendedorNome ?? '').isNotEmpty
                                                  ? ' (${p.vendedorNome})'
                                                  : ''),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Linha 3: resumo dos produtos
                                Text(
                                  resumo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: Colors.black87),
                                ),
                                const SizedBox(height: 6),
                                // Linha 4: localização/contato
                                if ((cidade ?? '').isNotEmpty || contatos != '—')
                                  Text(
                                    _maybeJoin([
                                      cidade?.trim().isNotEmpty == true
                                          ? 'Cidade: $cidade'
                                          : null,
                                      contatos != '—' ? 'Contato: $contatos' : null,
                                      if (cpfcnpj != null) 'CPF/CNPJ: $cpfcnpj',
                                    ]),
                                    style: small,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Total + menu + seta
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              PopupMenuButton<String>(
                                tooltip: 'Mais ações',
                                onSelected: (v) async {
                                  if (v == 'del') {
                                    await _confirmDelete(p);
                                  }
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                    value: 'del',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 20),
                                        SizedBox(width: 8),
                                        Text('Apagar pedido'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _fmtMoeda(p.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 20, color: Colors.black45),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
