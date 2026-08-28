// lib/tabs/clientes_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cliente.dart';
import '../services/supabase_service.dart';

const Color milkdimYellow = Color(0xFFFFE066);
const Color milkdimOrange = Color(0xFFE38A1D);
const Color milkdimWhite  = Color(0xFFFFFFFF);
const Color milkdimGrey   = Color(0xFFF7F7F7);

class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});
  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  final _service = SupabaseService();
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
      final data = await _service.buscarClientes(somenteAtivos: null);
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

  Color _badgeColor(int? dias) {
    if (dias == null) return Colors.grey.shade500;
    if (dias < 15) return Colors.green.shade700;
    if (dias < 30) return Colors.amber.shade800;
    return Colors.red.shade700;
  }

  Color _badgeBg(int? dias) {
    if (dias == null) return Colors.grey.shade600.withOpacity(0.15);
    if (dias < 15) return Colors.green.shade700.withOpacity(0.12);
    if (dias < 30) return Colors.amber.shade800.withOpacity(0.14);
    return Colors.red.shade700.withOpacity(0.14);
  }

  String _badgeText(int? dias) {
    if (dias == null) return 'Nunca';
    if (dias == 0) return 'Hoje';
    if (dias == 1) return '1 dia';
    return '$dias dias';
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[700] : milkdimOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
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
        backgroundColor: milkdimWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Remover Cliente',
              style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text('Tem certeza que deseja remover "${c.nome ?? '-'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: milkdimWhite),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
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
            backgroundColor: milkdimWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(
              children: [
                Icon(cliente == null ? Icons.person_add_alt_1 : Icons.edit, color: milkdimOrange),
                const SizedBox(width: 6),
                Text(
                  cliente == null ? 'Novo Cliente' : 'Editar Cliente',
                  style: const TextStyle(color: milkdimOrange, fontWeight: FontWeight.bold),
                ),
              ],
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
                          filled: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nomeFantasiaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome Fantasia',
                          prefixIcon: Icon(Icons.business),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: enderecoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Endereço',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          filled: true,
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),

                      // Cidade + CEP
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: cidadeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              prefixIcon: Icon(Icons.location_city),
                              filled: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: cepCtrl,
                            decoration: const InputDecoration(labelText: 'CEP', filled: true),
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
                                filled: true,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 140,
                            child: TextFormField(
                              controller: cepCtrl,
                              decoration: const InputDecoration(labelText: 'CEP', filled: true),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // CPF/CNPJ + Insc. Estadual
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: cpfCnpjCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CPF/CNPJ',
                              prefixIcon: Icon(Icons.assignment_ind),
                              filled: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: inscEstadualCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Insc. Estadual',
                              prefixIcon: Icon(Icons.confirmation_number),
                              filled: true,
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
                                filled: true,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: inscEstadualCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Insc. Estadual',
                                prefixIcon: Icon(Icons.confirmation_number),
                                filled: true,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Telefone + WhatsApp
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: telefoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Telefone',
                              prefixIcon: Icon(Icons.phone),
                              filled: true,
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: whatsappCtrl,
                            decoration: const InputDecoration(
                              labelText: 'WhatsApp',
                              prefixIcon: Icon(Icons.sms),
                              filled: true,
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
                                filled: true,
                              ),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: whatsappCtrl,
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp',
                                prefixIcon: Icon(Icons.sms),
                                filled: true,
                              ),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email),
                          filled: true,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: anotacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Anotação',
                          prefixIcon: Icon(Icons.notes),
                          filled: true,
                        ),
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Ativo', style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Switch(
                            value: ativo,
                            activeColor: milkdimOrange,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao salvar: ${e.message}'), backgroundColor: Colors.red[700]),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red[700]),
                    );
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: milkdimOrange, foregroundColor: milkdimWhite),
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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;

    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                filled: true,
                fillColor: milkdimWhite,
                hintText: 'Buscar por nome, cidade, CPF/CNPJ, telefone, WhatsApp, e-mail...',
                prefixIcon: const Icon(Icons.search, color: milkdimOrange),
                suffixIcon: (_searchCtrl.text.isEmpty)
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged();
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: milkdimYellow, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: milkdimOrange, width: 2.2),
                ),
              ),
            ),
          ),
          if (isWide) const SizedBox(width: 12),
          if (isWide)
            FilledButton.icon(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar'),
              style: FilledButton.styleFrom(backgroundColor: milkdimOrange, foregroundColor: milkdimWhite),
            ),
        ],
      ),
    );

    final listWidget = _loading
        ? const Center(child: CircularProgressIndicator(color: milkdimOrange))
        : _error != null
        ? Center(
      child: Text(
        _error!,
        style: const TextStyle(color: Colors.red, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    )
        : _filtered.isEmpty
        ? const Center(
      child: Text('Nenhum cliente encontrado.',
          style: TextStyle(color: milkdimOrange, fontSize: 18)),
    )
        : RefreshIndicator(
      onRefresh: _fetchClientes,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final c = _filtered[i];
          final lastDt = _asDate(c.ultimoPedido);
          final dias   = _diasDesde(lastDt);

          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _badgeBg(dias),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _badgeColor(dias).withOpacity(0.6)),
            ),
            child: Text(
              _badgeText(dias),
              style: TextStyle(color: _badgeColor(dias), fontWeight: FontWeight.w700),
            ),
          );

          final ultimoTxt = lastDt == null ? 'Nunca' : _dateFmt.format(lastDt);

          return Card(
            color: milkdimWhite,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 2.6,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: milkdimYellow,
                child: Icon(Icons.person_outline, color: milkdimOrange),
              ),
              title: Text(
                c.nome ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: milkdimOrange, fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((c.nomeFantasia ?? '').isNotEmpty) Text('Fantasia: ${c.nomeFantasia}'),
                  if ((c.telefone ?? '').isNotEmpty) Text('Telefone: ${c.telefone}'),
                  if ((c.whatsapp ?? '').isNotEmpty) Text('WhatsApp: ${c.whatsapp}'),
                  if ((c.email ?? '').isNotEmpty) Text('E-mail: ${c.email}'),
                  Text('Cidade: ${c.cidade ?? '-'}'),
                  Text('CPF/CNPJ: ${c.cpfCnpj ?? '-'}'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      badge,
                      const SizedBox(width: 10),
                      Text('Último: $ultimoTxt', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.ativo ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: c.ativo ? Colors.green.shade300 : Colors.red.shade300,
                          ),
                        ),
                        child: Text(
                          c.ativo ? 'Ativo' : 'Inativo',
                          style: TextStyle(
                            color: c.ativo ? Colors.green.shade800 : Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,

              // 👉 Tocar no item abre edição (pop-up)
              onTap: () => _showAddOrEditDialog(cliente: c),

              trailing: PopupMenuButton<String>(
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
                  const PopupMenuItem(
                    value: 'editar',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ativar',
                    child: ListTile(
                      leading: Icon(c.ativo ? Icons.visibility_off : Icons.visibility),
                      title: Text(c.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'remover',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Remover', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

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
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              backgroundColor: milkdimOrange,
              foregroundColor: milkdimWhite,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar Cliente'),
              elevation: 3,
            ),
          ),
      ],
    );
  }
}
