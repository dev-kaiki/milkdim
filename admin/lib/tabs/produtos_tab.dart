// lib/tabs/produtos_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../etiqueta/dialogo_tipos_caixa.dart';
import '../etiqueta/volumes.dart';
import '../models/produto.dart';
import '../services/caixas_service.dart';
import '../services/supabase_service.dart';
import '../widgets/lista_adaptavel.dart';

class ProdutosTab extends StatefulWidget {
  /// Só para captura visual: fonte dos produtos no lugar do Supabase.
  /// Nulo (padrão) usa [SupabaseService.buscarProdutos].
  @visibleForTesting
  final Future<List<Produto>> Function()? carregar;

  /// Só para testes: fonte dos tipos de caixa no lugar do Supabase.
  @visibleForTesting
  final FonteCaixas? fonteCaixas;

  /// Só para testes: grava o produto (insere se [id] é nulo) e devolve o id.
  @visibleForTesting
  final Future<int> Function(Map<String, dynamic> campos, int? id)? gravar;

  const ProdutosTab({super.key, this.carregar, this.fonteCaixas, this.gravar});

  @override
  State<ProdutosTab> createState() => _ProdutosTabState();
}

class _ProdutosTabState extends State<ProdutosTab> {
  late final _service = SupabaseService();
  final _searchCtrl = TextEditingController();

  final _brl = NumberFormat.simpleCurrency(locale: 'pt_BR');

  FonteCaixas? _caixas;
  FonteCaixas get _fonteCaixas =>
      _caixas ??= widget.fonteCaixas ?? CaixasService();
  List<TipoCaixa> _tipos = [];
  // Os tipos não carregaram: o campo de tipo fica indisponível no cadastro.
  bool _tiposFalhou = false;

  List<Produto> _produtos = [];
  List<Produto> _filtered = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchProdutos();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------- DATA --------------------

  Future<void> _fetchProdutos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.carregar?.call() ?? _service.buscarProdutos()); // List<Produto>
      if (!mounted) return;
      data.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      var tipos = <TipoCaixa>[];
      var falhou = false;
      try {
        tipos = await _fonteCaixas.tiposCaixa();
      } catch (_) {
        // Sem os tipos a lista segue funcionando; só não mostra o nome do tipo.
        falhou = true;
      }
      if (!mounted) return;
      setState(() {
        _tipos = tipos;
        _tiposFalhou = falhou;
        _produtos = data;
        _filtered = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => _filtered = _produtos);
        return;
      }
      setState(() {
        _filtered = _produtos.where((p) {
          bool c(String? s) => (s ?? '').toLowerCase().contains(q);
          return c(p.nome) || c(p.codigo) || c(p.unidade);
        }).toList();
      });
    });
  }

  // -------------------- HELPERS --------------------

  /// Parser de preço robusto:
  /// - "1.234,56" -> 1234.56
  /// - "1,234.56" -> 1234.56
  /// - "12,34"    -> 12.34
  /// - "12.34"    -> 12.34
  double _parsePreco(String input) {
    final s = input.trim().replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return double.nan;

    if (s.contains(',') && !s.contains('.')) {
      // caso típico pt-BR: vírgula decimal, sem ponto de milhar
      return double.tryParse(s.replaceAll(',', '.')) ?? double.nan;
    }

    if (s.contains(',') && s.contains('.')) {
      // decidir qual é decimal pelo último separador
      final lastComma = s.lastIndexOf(',');
      final lastDot   = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        // vírgula decimal; pontos = milhares
        final norm = s.replaceAll('.', '').replaceAll(',', '.');
        return double.tryParse(norm) ?? double.nan;
      } else {
        // ponto decimal; vírgulas = milhares
        final norm = s.replaceAll(',', '');
        // se tiver múltiplos pontos, mantém apenas o último como decimal
        final parts = norm.split('.');
        if (parts.length > 2) {
          final last = parts.removeLast();
          final intPart = parts.join('');
          return double.tryParse('$intPart.$last') ?? double.nan;
        }
        return double.tryParse(norm) ?? double.nan;
      }
    }

    if (s.contains('.')) {
      // estilo en-US, ponto decimal; remover pontos extra de milhar
      final parts = s.split('.');
      if (parts.length > 2) {
        final last = parts.removeLast();
        final intPart = parts.join('');
        return double.tryParse('$intPart.$last') ?? double.nan;
      }
      return double.tryParse(s) ?? double.nan;
    }

    // apenas dígitos
    return double.tryParse(s) ?? double.nan;
  }

  String _formatInicialPreco(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String? _nullIfEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  String _textoCaixa(Produto p) {
    final id = p.tipoCaixaId;
    if (id == null) return 'Avulso';
    for (final t in _tipos) {
      if (t.id == id) return 'Caixa: ${t.nome} (${t.capacidade})';
    }
    return 'Caixa';
  }

  Future<int> _gravarProduto(Map<String, dynamic> map, int? id) async {
    final g = widget.gravar;
    if (g != null) return g(map, id);
    final t = Supabase.instance.client.from('produtos');
    if (id == null) {
      final row = await t.insert(map).select('id').single();
      return (row['id'] as num).toInt();
    }
    await t.update(map).eq('id', id);
    return id;
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: error ? MdTipo.erro : MdTipo.sucesso);
  }

  // -------------------- CRUD --------------------

  Future<void> _toggleAtivo(Produto p, bool value) async {
    try {
      await Supabase.instance.client
          .from('produtos')
          .update({'ativo': value})
          .eq('id', p.id);
      await _fetchProdutos();
    } on PostgrestException catch (e) {
      _toast('Erro ao atualizar status: ${e.message}', error: true);
    } catch (e) {
      _toast('Erro ao atualizar status: $e', error: true);
    }
  }

  Future<void> _deleteProduto(Produto p) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const TituloDialogo(
            icone: Icons.delete_forever, texto: 'Remover Produto', destrutivo: true),
        content: Text('Tem certeza que deseja remover "${p.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          BotaoDestrutivo(texto: 'Remover', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('produtos').delete().eq('id', p.id);
      _toast('Produto removido');
      await _fetchProdutos();
    } on PostgrestException catch (e) {
      _toast('Não foi possível remover: ${e.message}', error: true);
    } catch (e) {
      _toast('Não foi possível remover (há vínculos em pedidos?): $e', error: true);
    }
  }

  Future<void> _showAddOrEditDialog({Produto? produto}) async {
    final formKey     = GlobalKey<FormState>();
    final codigoCtrl  = TextEditingController(text: produto?.codigo ?? '');
    final nomeCtrl    = TextEditingController(text: produto?.nome ?? '');
    final unidadeCtrl = TextEditingController(text: produto?.unidade ?? '');
    final precoCtrl   = TextEditingController(text: _formatInicialPreco(produto?.preco ?? 0.0));
    bool ativo        = produto?.ativo ?? true;
    int? tipoSel      = produto?.tipoCaixaId;
    final tipoOriginal = produto?.tipoCaixaId;
    String? falhaTipo;
    final tiposIndisponiveis = _tiposFalhou;
    // Tipos ativos; o tipo atual do produto aparece mesmo se estiver inativo.
    final opcoesTipo = _tipos.where((t) => t.ativo || t.id == tipoOriginal).toList();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // evita fechar sem querer
      builder: (context) {
        final maxW = MediaQuery.of(context).size.width;
        final dialogW = maxW < 420.0 ? maxW - 32.0 : (maxW < 720.0 ? 420.0 : 520.0);
        final isNarrow = dialogW < 420.0;

        return StatefulBuilder(
          builder: (context, setStateSB) => AlertDialog(
            title: TituloDialogo(
              icone: produto == null ? Icons.add_box : Icons.edit,
              texto: produto == null ? 'Novo Produto' : 'Editar Produto',
            ),
            content: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: dialogW),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Código + Unidade (responsivo sem LayoutBuilder)
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: codigoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Código',
                              prefixIcon: Icon(Icons.qr_code_2),
                            ),
                          ),
                          const SizedBox(height: MdSpace.md),
                          TextFormField(
                            controller: unidadeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Unidade (EX: CX, UN, KG)',
                              prefixIcon: Icon(Icons.straighten),
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codigoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Código',
                                prefixIcon: Icon(Icons.qr_code_2),
                              ),
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: TextFormField(
                              controller: unidadeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Unidade (EX: CX, UN, KG)',
                                prefixIcon: Icon(Icons.straighten),
                              ),
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: nomeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome *',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: precoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Preço *',
                          prefixIcon: Icon(Icons.attach_money),
                          helperText: 'Aceita vírgula ou ponto como separador',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Informe o preço';
                          final parsed = _parsePreco(v);
                          if (parsed.isNaN) return 'Preço inválido';
                          if (parsed < 0) return 'Preço não pode ser negativo';
                          return null;
                        },
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: MdSpace.md),
                      if (tiposIndisponiveis)
                        TextFormField(
                          enabled: false,
                          initialValue: 'Tipos de caixa indisponíveis',
                          decoration: const InputDecoration(
                            labelText: 'Tipo de caixa',
                            prefixIcon: Icon(Icons.inventory),
                          ),
                        )
                      else
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        initialValue: tipoSel,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de caixa',
                          prefixIcon: Icon(Icons.inventory),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Sem caixa (avulso)')),
                          for (final t in opcoesTipo)
                            DropdownMenuItem<int?>(
                              value: t.id,
                              child: Text(
                                '${t.nome} (${t.capacidade})${t.ativo ? '' : ' (desativado)'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (tipoOriginal != null &&
                              !opcoesTipo.any((t) => t.id == tipoOriginal))
                            DropdownMenuItem<int?>(
                                value: tipoOriginal, child: const Text('Tipo atual')),
                        ],
                        onChanged: (v) => setStateSB(() => tipoSel = v),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Text('Ativo', style: Theme.of(context).textTheme.titleSmall),
                          const Spacer(),
                          Switch(
                            value: ativo,
                            onChanged: (v) => setStateSB(() => ativo = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(produto == null ? 'Adicionar' : 'Salvar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final preco = _parsePreco(precoCtrl.text);

                  final map = <String, dynamic>{
                    'codigo'   : _nullIfEmpty(codigoCtrl.text),
                    'nome'     : nomeCtrl.text.trim(),
                    'unidade'  : _nullIfEmpty(unidadeCtrl.text)?.toUpperCase(),
                    'preco'    : preco,
                    'ativo'    : ativo,
                    'datahora' : DateTime.now().toIso8601String(),
                  };

                  try {
                    final id = await _gravarProduto(map, produto?.id);
                    if (!tiposIndisponiveis && tipoSel != tipoOriginal) {
                      try {
                        await _fonteCaixas.definirTipoDoProduto(id, tipoSel);
                      } catch (e) {
                        falhaTipo = e is RepoFailure ? e.message : '$e';
                      }
                    }
                    if (context.mounted) Navigator.pop(context, true);
                  } on PostgrestException catch (e) {
                    if (!context.mounted) return;
                    _toast('Erro ao salvar: ${e.message}', error: true);
                  } catch (e) {
                    if (!context.mounted) return;
                    _toast('Erro ao salvar: $e', error: true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      if (falhaTipo != null) {
        _toast('Produto salvo, mas o tipo de caixa não foi gravado: $falhaTipo',
            error: true);
      } else {
        _toast(produto == null ? 'Produto adicionado' : 'Produto atualizado');
      }
      await _fetchProdutos();
    }
  }

  Future<void> _abrirTiposCaixa() async {
    await mostrarDialogoTiposCaixa(context, _fonteCaixas);
    if (mounted) _fetchProdutos();
  }

  // -------------------- UI --------------------

  Widget _cartao(Produto p) {
    final tt = Theme.of(context).textTheme;
    return MdCard(
      // Tocar no item abre edição
      onTap: () => _showAddOrEditDialog(produto: p),
      padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.md, MdSpace.xs, MdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarLista(icone: Icons.inventory_2, ativo: p.ativo),
          const SizedBox(width: MdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Código: ${p.codigo ?? '-'} • Unidade: ${p.unidade ?? '-'}',
                  style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  _textoCaixa(p),
                  style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                ),
                const SizedBox(height: MdSpace.sm),
                SeloAtivo(ativo: p.ativo),
              ],
            ),
          ),
          const SizedBox(width: MdSpace.sm),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _brl.format(p.preco),
              style: tt.titleMedium,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            onSelected: (value) {
              switch (value) {
                case 'editar':
                  _showAddOrEditDialog(produto: p);
                  break;
                case 'ativar':
                  _toggleAtivo(p, !p.ativo);
                  break;
                case 'remover':
                  _deleteProduto(p);
                  break;
              }
            },
            itemBuilder: (_) => [
              itemMenu('editar', Icons.edit, 'Editar'),
              itemMenu(
                'ativar',
                p.ativo ? Icons.visibility_off : Icons.visibility,
                p.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo',
              ),
              const PopupMenuDivider(),
              itemMenu('remover', Icons.delete, 'Remover', destrutivo: true),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640.0;

    final header = BarraDaAba(
      busca: MdSearchField(
        controller: _searchCtrl,
        hint: 'Buscar por nome, código ou unidade...',
      ),
      acoes: [
        if (isWide)
          OutlinedButton.icon(
            onPressed: _abrirTiposCaixa,
            icon: const Icon(Icons.inventory),
            label: const Text('Tipos de caixa'),
          )
        else
          IconButton(
            tooltip: 'Tipos de caixa',
            onPressed: _abrirTiposCaixa,
            icon: const Icon(Icons.inventory),
          ),
        if (isWide)
          FilledButton.icon(
            onPressed: () => _showAddOrEditDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar'),
          ),
      ],
    );

    final Widget list;
    if (_loading) {
      list = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      list = ErroDaLista(texto: _error!);
    } else if (_filtered.isEmpty) {
      list = MdEmptyState(
        icone: Icons.inventory_2_outlined,
        titulo: 'Nenhum produto encontrado.',
        texto: _searchCtrl.text.trim().isEmpty ? null : 'Tente outro termo de busca.',
      );
    } else {
      list = ListaAdaptavel(
        onRefresh: _fetchProdutos,
        itemCount: _filtered.length,
        espacoFinal: isWide ? 0 : 72,
        itemBuilder: (context, i) => _cartao(_filtered[i]),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            header,
            Expanded(child: list),
          ],
        ),
        // FAB em telas estreitas
        if (!isWide)
          Positioned(
            right: MdSpace.lg,
            bottom: MdSpace.lg,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Produto'),
            ),
          ),
      ],
    );
  }
}
