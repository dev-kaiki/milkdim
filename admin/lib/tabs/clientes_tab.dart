// lib/tabs/clientes_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';
import '../services/supabase_service.dart';
import '../widgets/lista_adaptavel.dart';

class ClientesTab extends StatefulWidget {
  /// Só para captura visual: fonte dos clientes no lugar do Supabase.
  /// Nulo (padrão) usa [SupabaseService.buscarClientes] (ativos e inativos).
  @visibleForTesting
  final Future<List<Cliente>> Function()? carregar;

  const ClientesTab({super.key, this.carregar});
  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  late final _service = SupabaseService();
  final _searchCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yyyy');

  List<Cliente> _clientes = [];
  List<Cliente> _filtered = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchClientes();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------------------- DATA ---------------------

  Future<void> _fetchClientes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.carregar?.call() ?? _service.buscarClientes(somenteAtivos: null));
      if (!mounted) return;
      data.sort((a, b) => (a.nome ?? '').toLowerCase().compareTo((b.nome ?? '').toLowerCase()));
      setState(() {
        _clientes = data;
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
        setState(() => _filtered = _clientes);
        return;
      }
      setState(() {
        _filtered = _clientes.where((c) {
          bool contains(String? s) => (s ?? '').toLowerCase().contains(q);
          return contains(c.nome) ||
              contains(c.nomeFantasia) ||
              contains(c.cidade) ||
              contains(c.cpfCnpj) ||
              contains(c.telefone) ||
              contains(c.whatsapp) ||
              contains(c.email);
        }).toList();
      });
    });
  }

  // --------------------- HELPERS ---------------------

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String && v.isNotEmpty) {
      final d = DateTime.tryParse(v);
      return d?.toLocal();
    }
    return null;
  }

  int? _diasDesde(DateTime? dt) {
    if (dt == null) return null;
    final d = DateTime.now().difference(dt).inDays;
    return d < 0 ? 0 : d;
  }

  /// Recência do último pedido: < 15 dias sucesso, < 30 atenção, depois erro; nunca = neutro.
  MdTipo _badgeTipo(int? dias) {
    if (dias == null) return MdTipo.neutro;
    if (dias < 15) return MdTipo.sucesso;
    if (dias < 30) return MdTipo.atencao;
    return MdTipo.erro;
  }

  String _badgeText(int? dias) {
    if (dias == null) return 'Nunca';
    if (dias == 0) return 'Hoje';
    if (dias == 1) return '1 dia';
    return '$dias dias';
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: error ? MdTipo.erro : MdTipo.sucesso);
  }

  String? _nullIfEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  Map<String, dynamic> _clienteFormToMap({
    required String nome,
    String? nomeFantasia,
    String? endereco,
    String? cidade,
    String? cep,
    String? cpfCnpj,
    String? inscEstadual,
    String? telefone,
    String? whatsapp,
    String? email,
    String? anotacao,
    required bool ativo,
  }) {
    return {
      'nome'          : nome.trim(),
      'nome_fantasia' : _nullIfEmpty(nomeFantasia),
      'endereco'      : _nullIfEmpty(endereco),
      'cidade'        : _nullIfEmpty(cidade),
      'cep'           : _nullIfEmpty(cep),
      'cpf_cnpj'      : _nullIfEmpty(cpfCnpj),
      'insc_estadual' : _nullIfEmpty(inscEstadual),
      'telefone'      : _nullIfEmpty(telefone),
      'whatsapp'      : _nullIfEmpty(whatsapp),
      'email'         : _nullIfEmpty(email),
      'anotacao'      : _nullIfEmpty(anotacao),
      'ativo'         : ativo,
    };
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null;
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
    return ok ? null : 'E-mail inválido';
  }

  // --------------------- CRUD ---------------------

  Future<void> _toggleAtivo(Cliente c, bool value) async {
    try {
      await Supabase.instance.client
          .from('clientes')
          .update({'ativo': value})
          .eq('id', c.id);
      await _fetchClientes();
    } on PostgrestException catch (e) {
      _toast('Erro ao atualizar status: ${e.message}', error: true);
    } catch (e) {
      _toast('Erro ao atualizar status: $e', error: true);
    }
  }

  Future<void> _deleteCliente(Cliente c) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const TituloDialogo(
            icone: Icons.delete_forever, texto: 'Remover Cliente', destrutivo: true),
        content: Text('Tem certeza que deseja remover "${c.nome ?? '-'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          BotaoDestrutivo(texto: 'Remover', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client.from('clientes').delete().eq('id', c.id);
      _toast('Cliente removido');
      await _fetchClientes();
    } on PostgrestException catch (e) {
      _toast('Não foi possível remover: ${e.message}', error: true);
    } catch (e) {
      _toast('Não foi possível remover (há vínculos de pedidos?): $e', error: true);
    }
  }

  Future<void> _showAddOrEditDialog({Cliente? cliente}) async {
    final formKey = GlobalKey<FormState>();
    final nomeCtrl           = TextEditingController(text: cliente?.nome ?? '');
    final nomeFantasiaCtrl   = TextEditingController(text: cliente?.nomeFantasia ?? '');
    final enderecoCtrl       = TextEditingController(text: cliente?.endereco ?? '');
    final cidadeCtrl         = TextEditingController(text: cliente?.cidade ?? '');
    final cepCtrl            = TextEditingController(text: cliente?.cep ?? '');
    final cpfCnpjCtrl        = TextEditingController(text: cliente?.cpfCnpj ?? '');
    final inscEstadualCtrl   = TextEditingController(text: cliente?.inscEstadual ?? '');
    final telefoneCtrl       = TextEditingController(text: cliente?.telefone ?? '');
    final whatsappCtrl       = TextEditingController(text: cliente?.whatsapp ?? '');
    final emailCtrl          = TextEditingController(text: cliente?.email ?? '');
    final anotacaoCtrl       = TextEditingController(text: cliente?.anotacao ?? '');
    bool ativo               = cliente?.ativo ?? true;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // evita fechar sem querer
      builder: (context) {
        final maxW = MediaQuery.of(context).size.width;
        final double dialogW = maxW < 420.0 ? maxW - 32.0 : (maxW < 720.0 ? 420.0 : 520.0);
        final bool isNarrow = dialogW < 420.0;

        return StatefulBuilder(
          builder: (context, setStateSB) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: TituloDialogo(
              icone: cliente == null ? Icons.person_add_alt_1 : Icons.edit,
              texto: cliente == null ? 'Novo Cliente' : 'Editar Cliente',
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
                      TextFormField(
                        controller: nomeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome *',
                          prefixIcon: Icon(Icons.account_circle),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: nomeFantasiaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome Fantasia',
                          prefixIcon: Icon(Icons.business),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: enderecoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Endereço',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: MdSpace.md),

                      // Cidade + CEP
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: cidadeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              prefixIcon: Icon(Icons.location_city),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: MdSpace.md),
                          TextFormField(
                            controller: cepCtrl,
                            decoration: const InputDecoration(labelText: 'CEP'),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cidadeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cidade',
                                prefixIcon: Icon(Icons.location_city),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              controller: cepCtrl,
                              decoration: const InputDecoration(labelText: 'CEP'),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: MdSpace.md),

                      // CPF/CNPJ + Insc. Estadual
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: cpfCnpjCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CPF/CNPJ',
                              prefixIcon: Icon(Icons.assignment_ind),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: MdSpace.md),
                          TextFormField(
                            controller: inscEstadualCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Insc. Estadual',
                              prefixIcon: Icon(Icons.confirmation_number),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cpfCnpjCtrl,
                              decoration: const InputDecoration(
                                labelText: 'CPF/CNPJ',
                                prefixIcon: Icon(Icons.assignment_ind),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: TextFormField(
                              controller: inscEstadualCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Insc. Estadual',
                                prefixIcon: Icon(Icons.confirmation_number),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: MdSpace.md),

                      // Telefone + WhatsApp
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: telefoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Telefone',
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: MdSpace.md),
                          TextFormField(
                            controller: whatsappCtrl,
                            decoration: const InputDecoration(
                              labelText: 'WhatsApp',
                              prefixIcon: Icon(Icons.sms),
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      )
                          : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: telefoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Telefone',
                                prefixIcon: Icon(Icons.phone),
                              ),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: MdSpace.md),
                          Expanded(
                            child: TextFormField(
                              controller: whatsappCtrl,
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp',
                                prefixIcon: Icon(Icons.sms),
                              ),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: MdSpace.md),
                      TextFormField(
                        controller: anotacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Anotação',
                          prefixIcon: Icon(Icons.notes),
                        ),
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                      ),
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
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(cliente == null ? 'Adicionar' : 'Salvar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final data = _clienteFormToMap(
                    nome         : nomeCtrl.text,
                    nomeFantasia : nomeFantasiaCtrl.text,
                    endereco     : enderecoCtrl.text,
                    cidade       : cidadeCtrl.text,
                    cep          : cepCtrl.text,
                    cpfCnpj      : cpfCnpjCtrl.text,
                    inscEstadual : inscEstadualCtrl.text,
                    telefone     : telefoneCtrl.text,
                    whatsapp     : whatsappCtrl.text,
                    email        : emailCtrl.text,
                    anotacao     : anotacaoCtrl.text,
                    ativo        : ativo,
                  );

                  try {
                    if (cliente == null) {
                      await Supabase.instance.client.from('clientes').insert(data);
                    } else {
                      await Supabase.instance.client.from('clientes').update(data).eq('id', cliente.id);
                    }
                    if (context.mounted) Navigator.pop(context, true);
                  } on PostgrestException catch (e) {
                    if (!context.mounted) return;
                    showMdSnack(context, 'Erro ao salvar: ${e.message}', tipo: MdTipo.erro);
                  } catch (e) {
                    if (!context.mounted) return;
                    showMdSnack(context, 'Erro ao salvar: $e', tipo: MdTipo.erro);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      _toast(cliente == null ? 'Cliente adicionado' : 'Cliente atualizado');
      await _fetchClientes();
    }
  }

  // --------------------- UI ---------------------

  Widget _cartao(Cliente c) {
    final tt = Theme.of(context).textTheme;
    final lastDt = _asDate(c.ultimoPedido);
    final dias   = _diasDesde(lastDt);
    final ultimoTxt = lastDt == null ? 'Nunca' : _dateFmt.format(lastDt);

    return MdCard(
      // Tocar no item abre edição (pop-up)
      onTap: () => _showAddOrEditDialog(cliente: c),
      padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.md, MdSpace.xs, MdSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Em duas colunas o cartão estica até o vizinho: o rodapé fica embaixo.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarLista(icone: Icons.person_outline, ativo: c.ativo),
                  const SizedBox(width: MdSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.nome ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if ((c.nomeFantasia ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Fantasia: ${c.nomeFantasia}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                          ),
                        ],
                        const SizedBox(height: MdSpace.sm),
                        SeloAtivo(ativo: c.ativo),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais ações',
                    onSelected: (value) {
                      switch (value) {
                        case 'editar':
                          _showAddOrEditDialog(cliente: c);
                          break;
                        case 'ativar':
                          _toggleAtivo(c, !c.ativo);
                          break;
                        case 'remover':
                          _deleteCliente(c);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      itemMenu('editar', Icons.edit, 'Editar'),
                      itemMenu(
                        'ativar',
                        c.ativo ? Icons.visibility_off : Icons.visibility,
                        c.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo',
                      ),
                      const PopupMenuDivider(),
                      itemMenu('remover', Icons.delete, 'Remover', destrutivo: true),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: MdSpace.md),
              Padding(
                padding: const EdgeInsets.only(right: MdSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((c.telefone ?? '').isNotEmpty)
                      LinhaInfo(icone: Icons.phone_outlined, texto: 'Telefone: ${c.telefone}'),
                    if ((c.whatsapp ?? '').isNotEmpty)
                      LinhaInfo(icone: Icons.sms_outlined, texto: 'WhatsApp: ${c.whatsapp}'),
                    if ((c.email ?? '').isNotEmpty)
                      LinhaInfo(icone: Icons.email_outlined, texto: 'E-mail: ${c.email}'),
                    LinhaInfo(icone: Icons.location_city_outlined, texto: 'Cidade: ${c.cidade ?? '-'}'),
                    LinhaInfo(icone: Icons.badge_outlined, texto: 'CPF/CNPJ: ${c.cpfCnpj ?? '-'}'),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: MdSpace.md, right: MdSpace.md),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: MdSpace.md),
                Row(
                  children: [
                    MdStatusChip(
                      tipo: _badgeTipo(dias),
                      texto: _badgeText(dias),
                      icone: Icons.schedule,
                    ),
                    const SizedBox(width: MdSpace.md),
                    Expanded(
                      child: Text(
                        'Último: $ultimoTxt',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;

    final searchBar = BarraDaAba(
      busca: MdSearchField(
        controller: _searchCtrl,
        hint: 'Buscar por nome, cidade, CPF/CNPJ, telefone, WhatsApp, e-mail...',
      ),
      acoes: [
        if (isWide)
          FilledButton.icon(
            onPressed: () => _showAddOrEditDialog(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Adicionar'),
          ),
      ],
    );

    final Widget listWidget;
    if (_loading) {
      listWidget = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      listWidget = ErroDaLista(texto: _error!);
    } else if (_filtered.isEmpty) {
      listWidget = MdEmptyState(
        icone: Icons.groups_outlined,
        titulo: 'Nenhum cliente encontrado.',
        texto: _searchCtrl.text.trim().isEmpty ? null : 'Tente outro termo de busca.',
      );
    } else {
      listWidget = ListaAdaptavel(
        onRefresh: _fetchClientes,
        itemCount: _filtered.length,
        espacoFinal: isWide ? 0 : 72,
        itemBuilder: (context, i) => _cartao(_filtered[i]),
      );
    }

    // Usamos Stack para garantir FAB flutuante em telas estreitas,
    // mesmo estando dentro do conteúdo do Tab.
    return Stack(
      children: [
        Column(
          children: [
            searchBar,
            Expanded(child: listWidget),
          ],
        ),
        if (!isWide)
          Positioned(
            right: MdSpace.lg,
            bottom: MdSpace.lg,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar Cliente'),
            ),
          ),
      ],
    );
  }
}
