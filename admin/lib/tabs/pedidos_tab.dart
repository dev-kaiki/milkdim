// lib/tabs/pedidos_tab.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pedido.dart';
import '../widgets/lista_adaptavel.dart';

final supabase = Supabase.instance.client;

/// Lista de pedidos; ao tocar, abre detalhes formatados (usando `Pedido`)
/// e também mostra um bloco com **todas as colunas** (JSON bruto).
class PedidosTab extends StatefulWidget {
  /// Só para captura visual: fonte dos pedidos no lugar do Supabase.
  /// Nulo (padrão) busca na tabela `pedidos`.
  @visibleForTesting
  final Future<List<Pedido>> Function()? carregar;

  const PedidosTab({super.key, this.carregar});

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
      final List<Pedido> list;
      if (widget.carregar != null) {
        list = await widget.carregar!();
      } else {
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

        list = (rows as List)
            .map((m) => Pedido.fromMap(m as Map<String, dynamic>))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _pedidos = list;
        _filtered = list;
      });
    } catch (e) {
      if (!mounted) return;
      showMdSnack(context, 'Erro ao carregar pedidos: $e', tipo: MdTipo.erro);
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
        title: TituloDialogo(
          icone: Icons.delete_forever,
          texto: 'Apagar pedido #${p.id}?',
          destrutivo: true,
        ),
        content: const Text(
          'Esta ação não pode ser desfeita. Deseja realmente apagar este pedido?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          BotaoDestrutivo(
            texto: 'Apagar',
            onPressed: () => Navigator.of(ctx).pop(true),
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

      showMdSnack(context, 'Pedido #$id apagado com sucesso.', tipo: MdTipo.sucesso);
      return true;
    } catch (e) {
      if (!mounted) return false;
      showMdSnack(context, 'Erro ao apagar pedido #$id: $e', tipo: MdTipo.erro);
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
      showMdSnack(context, 'Erro ao carregar detalhes do pedido #$id: $e', tipo: MdTipo.erro);
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

  /// Finalizado = sucesso, cancelado = erro, pendente/aguardando = atenção, demais = info.
  MdTipo _statusTipo(String status) {
    final s = status.toLowerCase();
    if (s.contains('final')) return MdTipo.sucesso;
    if (s.contains('cancel')) return MdTipo.erro;
    if (s.contains('pend') || s.contains('aguard')) return MdTipo.atencao;
    return MdTipo.info;
  }

  Widget _statusChip(String status) => MdStatusChip(tipo: _statusTipo(status), texto: status);

  String _maybeJoin(List<String?> parts) {
    final filt = parts.where((e) => e != null && e.trim().isNotEmpty).cast<String>().toList();
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

  String _vendedorTexto(Pedido p) =>
      (p.vendedorCodigo ?? '') +
      ((p.vendedorNome ?? '').isNotEmpty ? ' (${p.vendedorNome})' : '');

  bool _temVendedor(Pedido p) =>
      (p.vendedorCodigo ?? '').isNotEmpty || (p.vendedorNome ?? '').isNotEmpty;

  Future<void> _copy(String label, String? value) async {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    showMdSnack(context, '$label copiado');
  }

  Widget _rotulo(String label) => SizedBox(
        width: 140,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: MdColors.textMuted),
        ),
      );

  /// Bloco monoespaçado (JSON) selecionável.
  Widget _blocoCodigo(String texto) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MdRadius.field),
          color: MdColors.background,
          border: Border.all(color: MdColors.border),
        ),
        padding: const EdgeInsets.all(MdSpace.md),
        child: SelectableText(
          texto,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3),
        ),
      );

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

    final Widget valueWidget = isJsonBlock ? _blocoCodigo(v) : Text(v);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rotulo(label),
          const SizedBox(width: MdSpace.sm),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  // (Opcional) quando quiser renderizar um widget no valor:
  Widget infoRowWidget(String label, Widget value, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rotulo(label),
          const SizedBox(width: MdSpace.sm),
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
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MdSpace.xl, 0, MdSpace.xl, MdSpace.lg),
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
                final tt = Theme.of(context).textTheme;

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
                              child: Text(clienteTitulo, style: tt.titleLarge),
                            ),
                            IconButton(
                              tooltip: 'Apagar pedido',
                              color: MdColors.danger,
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
                        const SizedBox(height: MdSpace.sm),
                        Wrap(
                          spacing: MdSpace.sm,
                          runSpacing: MdSpace.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _statusChip(ped.status),
                            if ((ped.numero ?? '').isNotEmpty)
                              Chip(label: Text('Nº ${ped.numero}')),
                            Chip(label: Text('ID ${ped.id}')),
                            Chip(label: Text('Total: ${_fmtMoeda(ped.total)}')),
                            Chip(label: Text('Itens: ${ped.totalItens}')),
                            if (_temVendedor(ped))
                              Chip(
                                avatar: const Icon(Icons.badge_outlined, size: 18),
                                label: Text(_vendedorTexto(ped)),
                              ),
                            Chip(label: Text('Quando: ${_fmtData(ped.datahora)}')),
                          ],
                        ),
                        const SizedBox(height: MdSpace.lg),
                        const Divider(),

                        // ITENS
                        const SizedBox(height: MdSpace.md),
                        const MdSectionHeader(titulo: 'Itens do pedido'),
                        MdCard(
                          padding: EdgeInsets.zero,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingTextStyle: tt.labelLarge!.copyWith(color: MdColors.textMuted),
                              columns: const [
                                DataColumn(label: Text('Produto')),
                                DataColumn(label: Text('Preço'), numeric: true),
                                DataColumn(label: Text('Qtd'), numeric: true),
                                DataColumn(label: Text('Subtotal'), numeric: true),
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
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: MdSpace.md, right: MdSpace.xs),
                            child: Text('Total: ${_fmtMoeda(ped.total)}', style: tt.titleMedium),
                          ),
                        ),

                        // CLIENTE
                        const SizedBox(height: MdSpace.lg),
                        const Divider(),
                        const SizedBox(height: MdSpace.md),
                        const MdSectionHeader(titulo: 'Dados do cliente'),
                        _infoRow('Código (ID)', ped.clienteId, dense: true),
                        _infoRow('Nome', ped.clienteNome, dense: true),
                        _infoRow('Nome fantasia', ped.clienteNomeFantasia, dense: true),
                        infoRowWidget(
                          'Telefone/WhatsApp',
                          Wrap(spacing: MdSpace.sm, runSpacing: MdSpace.sm, children: [
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
                        const SizedBox(height: MdSpace.lg),
                        const Divider(),
                        const SizedBox(height: MdSpace.md),
                        const MdSectionHeader(titulo: 'Vendedor'),
                        _infoRow('Código', ped.vendedorCodigo),
                        _infoRow('Nome', ped.vendedorNome),

                        // DADOS BRUTOS / TODAS AS COLUNAS
                        const SizedBox(height: MdSpace.lg),
                        const Divider(),
                        const SizedBox(height: MdSpace.md),
                        MdSectionHeader(
                          titulo: 'Dados brutos (todas as colunas)',
                          trailing: IconButton(
                            tooltip: 'Copiar JSON',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: jsonStr));
                              if (!mounted) return;
                              showMdSnack(
                                  context, 'JSON copiado para a área de transferência.');
                            },
                            icon: const Icon(Icons.copy_rounded),
                          ),
                        ),
                        _blocoCodigo(jsonStr),
                        const SizedBox(height: MdSpace.lg),
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

  Widget _cartao(Pedido p, {required bool largo}) {
    final tt = Theme.of(context).textTheme;
    final cliente = (p.clienteNome ?? p.clienteNomeFantasia ?? '—').toString();
    final status = p.status;
    final numero = (p.numero ?? '').toString();
    final cidade = p.clienteCidade;
    final contatos = _maybeJoin([p.clienteTelefone, p.clienteWhatsapp, p.clienteEmail]);
    final cpfcnpj = (p.clienteCpfCnpj ?? '').trim().isEmpty ? null : p.clienteCpfCnpj;
    final resumo = _produtosResumo(p.itens);
    final localContato = (cidade ?? '').isNotEmpty || contatos != '—'
        ? _maybeJoin([
            cidade?.trim().isNotEmpty == true ? 'Cidade: $cidade' : null,
            contatos != '—' ? 'Contato: $contatos' : null,
            if (cpfcnpj != null) 'CPF/CNPJ: $cpfcnpj',
          ])
        : null;

    final menu = PopupMenuButton<String>(
      tooltip: 'Mais ações',
      onSelected: (v) async {
        if (v == 'del') {
          await _confirmDelete(p);
        }
      },
      itemBuilder: (ctx) => [
        itemMenu('del', Icons.delete_outline, 'Apagar pedido', destrutivo: true),
      ],
    );

    // Linha 2: status + metadados
    final metas = Wrap(
      spacing: MdSpace.lg,
      runSpacing: MdSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _statusChip(status),
        if (numero.isNotEmpty) LinhaInfo(icone: Icons.tag, texto: 'Nº $numero'),
        LinhaInfo(icone: Icons.shopping_basket_outlined, texto: 'Itens: ${p.totalItens}'),
        LinhaInfo(icone: Icons.schedule, texto: _fmtData(p.datahora)),
        if (_temVendedor(p)) LinhaInfo(icone: Icons.badge_outlined, texto: _vendedorTexto(p)),
      ],
    );

    return MdCard(
      onTap: () => _openDetalhesPedido(p),
      padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.md, MdSpace.xs, MdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarLista(letra: (cliente.isNotEmpty ? cliente[0] : '?').toUpperCase()),
          const SizedBox(width: MdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha 1: nome do cliente (+ total, no celular)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cliente,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!largo) ...[
                      const SizedBox(width: MdSpace.sm),
                      Text(_fmtMoeda(p.total), style: tt.titleMedium),
                    ],
                  ],
                ),
                const SizedBox(height: MdSpace.sm),
                metas,
                const SizedBox(height: MdSpace.sm),
                // Linha 3: resumo dos produtos
                Text(
                  resumo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium,
                ),
                // Linha 4: localização/contato
                if (localContato != null) ...[
                  const SizedBox(height: MdSpace.xs),
                  Text(
                    localContato,
                    maxLines: largo ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (largo) ...[
            const SizedBox(width: MdSpace.lg),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_fmtMoeda(p.total), style: tt.titleLarge),
            ),
            const SizedBox(width: MdSpace.xs),
          ],
          menu,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;
    final Widget iconeAtualizar = _loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh);

    final Widget lista;
    if (_loading) {
      lista = const Center(child: CircularProgressIndicator());
    } else if (_filtered.isEmpty) {
      // Lista rolável para manter o "puxar para atualizar" com a lista vazia.
      lista = RefreshIndicator(
        onRefresh: _fetchPedidos,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            MdEmptyState(
              icone: Icons.receipt_long_outlined,
              titulo: 'Nenhum pedido encontrado.',
              texto: _searchCtrl.text.trim().isEmpty ? null : 'Tente outro termo de busca.',
            ),
          ],
        ),
      );
    } else {
      lista = LayoutBuilder(
        builder: (context, c) {
          final largo = c.maxWidth >= larguraDuasColunas;
          return ListaAdaptavel(
            onRefresh: _fetchPedidos,
            itemCount: _filtered.length,
            permitirDuasColunas: false,
            itemBuilder: (_, i) => _cartao(_filtered[i], largo: largo),
          );
        },
      );
    }

    return Column(
      children: [
        // 🔎 busca + 🔄 atualizar
        BarraDaAba(
          busca: MdSearchField(
            controller: _searchCtrl,
            hint: 'Buscar por cliente, status, número, ID, cidade, contato, CPF/CNPJ, produto…',
          ),
          acoes: [
            if (isWide)
              OutlinedButton.icon(
                onPressed: _loading ? null : _fetchPedidos,
                icon: iconeAtualizar,
                label: const Text('Atualizar'),
              )
            else
              // Celular: só o ícone, para a busca ter espaço.
              IconButton.outlined(
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _fetchPedidos,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: MdColors.primaryStrong,
                  side: const BorderSide(color: MdColors.border),
                  backgroundColor: MdColors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MdRadius.field)),
                ),
                icon: iconeAtualizar,
              ),
          ],
        ),

        // 📋 lista
        Expanded(child: lista),
      ],
    );
  }
}
