// lib/tabs/vendedores_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vendedor.dart';
import '../services/supabase_service.dart';
import '../widgets/lista_adaptavel.dart';

class VendedoresTab extends StatefulWidget {
  /// Só para captura visual: fonte dos vendedores no lugar do Supabase.
  /// Nulo (padrão) usa [SupabaseService.buscarVendedores].
  @visibleForTesting
  final Future<List<Vendedor>> Function()? carregar;

  const VendedoresTab({super.key, this.carregar});

  @override
  State<VendedoresTab> createState() => _VendedoresTabState();
}

class _VendedoresTabState extends State<VendedoresTab> {
  late final _service = SupabaseService();
  final _searchCtrl = TextEditingController();

  List<Vendedor> _vendedores = [];
  List<Vendedor> _filtered = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchVendedores();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------- HELPERS --------------------

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: error ? MdTipo.erro : MdTipo.sucesso);
  }

  String? _nullIfEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Texto legivel para o admin: mensagem do servidor, nunca stack.
  String _msgErro(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42501') return 'Sem permissao para esta operacao.';
      if (e.message.isNotEmpty) return e.message;
    }
    return '$e';
  }

  // -------------------- DATA --------------------

  Future<void> _fetchVendedores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.carregar?.call() ?? _service.buscarVendedores()); // List<Vendedor>
      if (!mounted) return;
      data.sort((a, b) => (a.nome ?? '').toLowerCase().compareTo((b.nome ?? '').toLowerCase()));
      setState(() {
        _vendedores = data;
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
        setState(() => _filtered = _vendedores);
        return;
      }
      setState(() {
        _filtered = _vendedores.where((v) {
          bool contains(String? s) => (s ?? '').toLowerCase().contains(q);
          return contains(v.nome) || contains(v.codigo) || contains(v.anotacao);
        }).toList();
      });
    });
  }

  Future<void> _toggleAtivo(Vendedor v, bool value) async {
    try {
      await _service.definirAtivoVendedor(v.codigo, value);
      await _fetchVendedores();
    } catch (e) {
      _toast('Erro ao atualizar status: ${_msgErro(e)}', error: true);
    }
  }

  Future<void> _delete(Vendedor v) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const TituloDialogo(
            icone: Icons.delete_forever, texto: 'Remover Vendedor', destrutivo: true),
        content: Text('Tem certeza que deseja remover "${v.nome ?? '-'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          BotaoDestrutivo(texto: 'Remover', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.excluirVendedor(v.codigo);
      _toast('Vendedor removido');
      await _fetchVendedores();
    } catch (e) {
      _toast('Erro ao remover: ${_msgErro(e)}', error: true);
    }
  }

  Future<void> _trocarSenha(Vendedor v) async {
    final formKey = GlobalKey<FormState>();
    final senhaCtrl = TextEditingController();
    bool hidePwd = true;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: const TituloDialogo(icone: Icons.lock_reset, texto: 'Trocar senha'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vendedor: ${v.nome} (${v.codigo})'),
                const SizedBox(height: MdSpace.lg),
                TextFormField(
                  controller: senhaCtrl,
                  obscureText: hidePwd,
                  decoration: InputDecoration(
                    labelText: 'Nova senha *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(hidePwd ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setStateSB(() => hidePwd = !hidePwd),
                    ),
                  ),
                  validator: (x) =>
                      (x == null || x.length < 6) ? 'A senha precisa ter ao menos 6 caracteres.' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancelar')),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await _service.alterarSenhaVendedor(v.codigo, senhaCtrl.text);
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                } catch (e) {
                  _toast('Erro ao trocar senha: ${_msgErro(e)}', error: true);
                }
              },
            ),
          ],
        ),
      ),
    );
    senhaCtrl.dispose();
    if (saved == true) _toast('Senha alterada');
  }

  Future<void> _showAddOrEditDialog({Vendedor? vendedor}) async {
    final formKey = GlobalKey<FormState>();
    final codigoCtrl   = TextEditingController(text: vendedor?.codigo ?? '');
    final nomeCtrl     = TextEditingController(text: vendedor?.nome ?? '');
    final senhaCtrl    = TextEditingController(); // so ao criar
    final anotacaoCtrl = TextEditingController(text: vendedor?.anotacao ?? '');
    bool ativo         = vendedor?.ativo ?? true;
    bool hidePwd       = true;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // evita fechar sem querer
      builder: (dialogCtx) {
        final screenW = MediaQuery.of(dialogCtx).size.width;
        final double dialogW = screenW < 420.0 ? (screenW - 32.0) : (screenW < 720.0 ? 420.0 : 520.0);
        final bool isNarrow = dialogW < 420.0;

        return StatefulBuilder(
          builder: (context, setStateSB) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: TituloDialogo(
              icone: vendedor == null ? Icons.person_add_alt : Icons.edit,
              texto: vendedor == null ? 'Novo Vendedor' : 'Editar Vendedor',
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
                      // Código + Nome (responsivo sem LayoutBuilder)
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: codigoCtrl,
                            readOnly: vendedor != null,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Código *',
                              prefixIcon: Icon(Icons.badge),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
                          ),
                          const SizedBox(height: MdSpace.md),
                          TextFormField(
                            controller: nomeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome *',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codigoCtrl,
                              readOnly: vendedor != null,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Código *',
                                prefixIcon: Icon(Icons.badge),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: TextFormField(
                              controller: nomeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome *',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                            ),
                          ),
                        ],
                      ),
                      if (vendedor == null) ...[
                        const SizedBox(height: MdSpace.md),
                        TextFormField(
                          controller: senhaCtrl,
                          obscureText: hidePwd,
                          decoration: InputDecoration(
                            labelText: 'Senha *',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(hidePwd ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setStateSB(() => hidePwd = !hidePwd),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'A senha precisa ter ao menos 6 caracteres.'
                              : null,
                        ),
                      ],
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: anotacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Anotação',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                        ),
                        maxLines: 2,
                      ),
                      if (vendedor == null) ...[
                        const SizedBox(height: 8),
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
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancelar')),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(vendedor == null ? 'Adicionar' : 'Salvar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  try {
                    if (vendedor == null) {
                      await _service.criarVendedor(
                        codigo: codigoCtrl.text.trim(),
                        nome: nomeCtrl.text.trim(),
                        senha: senhaCtrl.text,
                        anotacao: _nullIfEmpty(anotacaoCtrl.text),
                        ativo: ativo,
                      );
                    } else {
                      // so nome e anotacao: mudar o codigo moveria os pedidos do vendedor
                      await Supabase.instance.client.from('vendedores').update({
                        'nome': nomeCtrl.text.trim(),
                        'anotacao': _nullIfEmpty(anotacaoCtrl.text),
                      }).eq('id', vendedor.id);
                    }
                    if (mounted) Navigator.of(dialogCtx).pop(true);
                  } catch (e) {
                    _toast('Erro ao salvar: ${_msgErro(e)}', error: true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      _toast(vendedor == null ? 'Vendedor adicionado' : 'Vendedor atualizado');
      await _fetchVendedores();
    }
  }

  // -------------------- UI --------------------

  Widget _cartao(Vendedor v) {
    final tt = Theme.of(context).textTheme;
    return MdCard(
      // Tocar no item abre edição
      onTap: () => _showAddOrEditDialog(vendedor: v),
      padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.md, MdSpace.xs, MdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarLista(icone: Icons.person, ativo: v.ativo),
          const SizedBox(width: MdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Código: ${v.codigo}',
                  style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                ),
                if ((v.anotacao ?? '').isNotEmpty) ...[
                  const SizedBox(height: MdSpace.xs),
                  LinhaInfo(
                    icone: Icons.note_alt_outlined,
                    texto: 'Anotação: ${v.anotacao}',
                    maxLines: 2,
                  ),
                ],
                const SizedBox(height: MdSpace.sm),
                SeloAtivo(ativo: v.ativo),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            onSelected: (value) {
              switch (value) {
                case 'editar':
                  _showAddOrEditDialog(vendedor: v);
                  break;
                case 'senha':
                  _trocarSenha(v);
                  break;
                case 'ativar':
                  _toggleAtivo(v, !v.ativo);
                  break;
                case 'remover':
                  _delete(v);
                  break;
              }
            },
            itemBuilder: (_) => [
              itemMenu('editar', Icons.edit, 'Editar'),
              itemMenu('senha', Icons.lock_reset, 'Trocar senha'),
              itemMenu(
                'ativar',
                v.ativo ? Icons.visibility_off : Icons.visibility,
                v.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo',
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
    final isWide = MediaQuery.of(context).size.width >= 640;

    final Widget lista;
    if (_loading) {
      lista = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      lista = ErroDaLista(texto: _error!);
    } else if (_filtered.isEmpty) {
      lista = MdEmptyState(
        icone: Icons.people_alt_outlined,
        titulo: 'Nenhum vendedor encontrado.',
        texto: _searchCtrl.text.trim().isEmpty ? null : 'Tente outro termo de busca.',
      );
    } else {
      lista = ListaAdaptavel(
        onRefresh: _fetchVendedores,
        itemCount: _filtered.length,
        espacoFinal: isWide ? 0 : 72,
        itemBuilder: (context, i) => _cartao(_filtered[i]),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // Busca + Ação (responsivo)
            BarraDaAba(
              busca: MdSearchField(
                controller: _searchCtrl,
                hint: 'Buscar por nome ou código...',
              ),
              acoes: [
                if (isWide)
                  FilledButton.icon(
                    onPressed: () => _showAddOrEditDialog(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Adicionar'),
                  ),
              ],
            ),
            Expanded(child: lista),
          ],
        ),

        // FAB (telas estreitas)
        if (!isWide)
          Positioned(
            right: MdSpace.lg,
            bottom: MdSpace.lg,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar Vendedor'),
            ),
          ),
      ],
    );
  }
}
