// lib/tabs/pedidos_tab.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pedido.dart';
import '../widgets/detalhe_pedido.dart';
import '../widgets/lista_adaptavel.dart';

final supabase = Supabase.instance.client;

/// Lista de pedidos; ao tocar, abre detalhes formatados (usando `Pedido`)
/// e também mostra um bloco com **todas as colunas** (JSON bruto).
class PedidosTab extends StatefulWidget {
  /// Só para captura visual: fonte dos pedidos no lugar do Supabase.
  /// Nulo (padrão) busca na tabela `pedidos`.
  @visibleForTesting
  final Future<List<Pedido>> Function()? carregar;

  /// Só para testes: busca do detalhe ao tocar; nulo usa [buscarDetalhePedido].
  @visibleForTesting
  final Future<DetalheDoPedido> Function(int id)? buscarDetalhe;

  const PedidosTab({super.key, this.carregar, this.buscarDetalhe});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Pedido> _pedidos = [];
  List<Pedido> _filtered = [];

  /// Situação escolhida no filtro: null = todos; senão o status ('salvo', ...).
  String? _situacao;

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
              'numero, produtos, enviado_em, alterado_em, finalizado_em, finalizado_por, '
              'finalizado_manual, cancelado_em, cancelado_por',
        )
            .order('datahora', ascending: false);

        list = (rows as List)
            .map((m) => Pedido.fromMap(m as Map<String, dynamic>))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _pedidos = list;
      });
      _aplicarFiltros();
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

  // -------------------- SEARCH --------------------

  void _onSearch() => _aplicarFiltros();

  /// Aplica busca + filtro de situação sobre a lista já carregada.
  void _aplicarFiltros() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _pedidos.where((p) {
        if (_situacao != null && p.status != _situacao) return false;
        if (q.isEmpty) return true;
        String s(Object? x) => (x ?? '').toString().toLowerCase();
        return s(p.clienteNome).contains(q) ||
            s(p.clienteNomeFantasia).contains(q) ||
            p.status.toLowerCase().contains(q) ||
            p.situacaoTexto.toLowerCase().contains(q) ||
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

  // -------------------- UI (lista com pré-visualização rica) --------------------

  Widget _cartao(Pedido p, {required bool largo}) {
    final tt = Theme.of(context).textTheme;
    final cliente = (p.clienteNome ?? p.clienteNomeFantasia ?? '—').toString();
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
        chipSituacao(p),
        if (numero.isNotEmpty) LinhaInfo(icone: Icons.tag, texto: 'Nº $numero'),
        LinhaInfo(icone: Icons.shopping_basket_outlined, texto: 'Itens: ${p.totalItens}'),
        LinhaInfo(icone: Icons.schedule, texto: fmtDataPedido(p.datahora)),
        if (temVendedorPedido(p)) LinhaInfo(icone: Icons.badge_outlined, texto: vendedorTextoPedido(p)),
      ],
    );

    return MdCard(
      onTap: () => abrirDetalhesPedido(context, p,
          buscar: widget.buscarDetalhe, apagar: _confirmDelete),
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
                      Text(fmtMoedaPedido(p.total), style: tt.titleMedium),
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
              child: Text(fmtMoedaPedido(p.total), style: tt.titleLarge),
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

        // Situação
        Padding(
          padding: const EdgeInsets.fromLTRB(MdSpace.lg, 0, MdSpace.lg, MdSpace.sm),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: MdSpace.sm),
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
            segments: const [
              ButtonSegment(value: 'todos', label: Text('Todos', maxLines: 1, softWrap: false)),
              ButtonSegment(value: 'salvo', label: Text('Em aberto', maxLines: 1, softWrap: false)),
              ButtonSegment(
                  value: 'finalizado', label: Text('Finalizados', maxLines: 1, softWrap: false)),
              ButtonSegment(
                  value: 'cancelado', label: Text('Cancelados', maxLines: 1, softWrap: false)),
            ],
            selected: {_situacao ?? 'todos'},
            onSelectionChanged: (v) {
              _situacao = v.first == 'todos' ? null : v.first;
              _aplicarFiltros();
            },
          ),
        ),

        // 📋 lista
        Expanded(child: lista),
      ],
    );
  }
}
