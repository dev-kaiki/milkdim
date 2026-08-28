// lib/tabs/vendedores_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vendedor.dart';
import '../services/supabase_service.dart';

const Color milkdimYellow = Color(0xFFFFE066);
const Color milkdimOrange = Color(0xFFE38A1D);
const Color milkdimWhite  = Color(0xFFFFFFFF);
const Color milkdimGrey   = Color(0xFFF7F7F7);

class VendedoresTab extends StatefulWidget {
  const VendedoresTab({super.key});

  @override
  State<VendedoresTab> createState() => _VendedoresTabState();
}

class _VendedoresTabState extends State<VendedoresTab> {
  final _service = SupabaseService();
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

  // -------------------- DATA --------------------

  Future<void> _fetchVendedores() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.buscarVendedores(); // List<Vendedor>
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
      await Supabase.instance.client
          .from('vendedores')
          .update({'ativo': value})
          .eq('id', v.id);
      await _fetchVendedores();
    } on PostgrestException catch (e) {
      _toast('Erro ao atualizar status: ${e.message}', error: true);
    } catch (e) {
      _toast('Erro ao atualizar status: $e', error: true);
    }
  }

  Future<void> _delete(Vendedor v) async {
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
            Text('Remover Vendedor',
                style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Tem certeza que deseja remover "${v.nome ?? '-'}"?'),
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
      await Supabase.instance.client.from('vendedores').delete().eq('id', v.id);
      _toast('Vendedor removido');
      await _fetchVendedores();
    } on PostgrestException catch (e) {
      _toast('Erro ao remover: ${e.message}', error: true);
    } catch (e) {
      _toast('Erro ao remover: $e', error: true);
    }
  }

  Future<void> _showAddOrEditDialog({Vendedor? vendedor}) async {
    final formKey = GlobalKey<FormState>();
    final codigoCtrl   = TextEditingController(text: vendedor?.codigo ?? '');
    final nomeCtrl     = TextEditingController(text: vendedor?.nome ?? '');
    final senhaCtrl    = TextEditingController(); // opcional ao editar
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
            backgroundColor: milkdimWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(
              children: [
                Icon(vendedor == null ? Icons.person_add_alt : Icons.edit, color: milkdimOrange),
                const SizedBox(width: 6),
                Text(
                  vendedor == null ? 'Novo Vendedor' : 'Editar Vendedor',
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
                      // Código + Nome (responsivo sem LayoutBuilder)
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: codigoCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Código *',
                              prefixIcon: Icon(Icons.badge),
                              filled: true,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: nomeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome *',
                              prefixIcon: Icon(Icons.person_outline),
                              filled: true,
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
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Código *',
                                prefixIcon: Icon(Icons.badge),
                                filled: true,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: nomeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome *',
                                prefixIcon: Icon(Icons.person_outline),
                                filled: true,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: senhaCtrl,
                        obscureText: hidePwd,
                        decoration: InputDecoration(
                          labelText: vendedor == null ? 'Senha *' : 'Nova senha (opcional)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          filled: true,
                          suffixIcon: IconButton(
                            icon: Icon(hidePwd ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setStateSB(() => hidePwd = !hidePwd),
                          ),
                        ),
                        validator: (v) {
                          if (vendedor == null && (v == null || v.isEmpty)) return 'Informe a senha';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: anotacaoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Anotação',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                          filled: true,
                        ),
                        maxLines: 2,
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
              TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancelar')),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(vendedor == null ? 'Adicionar' : 'Salvar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final data = <String, dynamic>{
                    'codigo'  : codigoCtrl.text.trim(),
                    'nome'    : nomeCtrl.text.trim(),
                    'ativo'   : ativo,
                    'anotacao': _nullIfEmpty(anotacaoCtrl.text),
                  };
                  if (vendedor == null) {
                    data['senha'] = senhaCtrl.text; // obrigatório ao criar
                  } else if (senhaCtrl.text.isNotEmpty) {
                    data['senha'] = senhaCtrl.text;  // opcional no update
                  }

                  try {
                    if (vendedor == null) {
                      await Supabase.instance.client.from('vendedores').insert(data);
                    } else {
                      await Supabase.instance.client.from('vendedores').update(data).eq('id', vendedor.id);
                    }
                    if (mounted) Navigator.of(dialogCtx).pop(true);
                  } on PostgrestException catch (e) {
                    // 23505 = unique_violation
                    if ((e.code ?? '') == '23505') {
                      _toast('Código já utilizado por outro vendedor.', error: true);
                    } else {
                      _toast('Erro ao salvar: ${e.message}', error: true);
                    }
                  } catch (e) {
                    _toast('Erro ao salvar: $e', error: true);
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
      _toast(vendedor == null ? 'Vendedor adicionado' : 'Vendedor atualizado');
      await _fetchVendedores();
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640;

    return Column(
      children: [
        // Busca + Ação (responsivo)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: milkdimWhite,
                    hintText: 'Buscar por nome ou código...',
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
        ),

        // Lista
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: milkdimOrange))
              : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _filtered.isEmpty
              ? const Center(
            child: Text('Nenhum vendedor encontrado.',
                style: TextStyle(color: milkdimOrange, fontSize: 18)),
          )
              : RefreshIndicator(
            onRefresh: _fetchVendedores,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final v = _filtered[i];

                return Card(
                  color: milkdimWhite,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 2.8,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: v.ativo ? milkdimOrange.withOpacity(.15) : milkdimGrey,
                      child: Icon(Icons.person,
                          color: v.ativo ? milkdimOrange : Colors.grey),
                    ),
                    title: Text(
                      v.nome ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: milkdimOrange, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Código: ${v.codigo ?? '-'}'),
                        if ((v.anotacao ?? '').isNotEmpty)
                          Text(
                            'Anotação: ${v.anotacao}',
                            style: const TextStyle(fontSize: 13, color: Colors.black54),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: v.ativo ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: v.ativo ? Colors.green.shade300 : Colors.red.shade300,
                            ),
                          ),
                          child: Text(
                            v.ativo ? 'Ativo' : 'Inativo',
                            style: TextStyle(
                              color: v.ativo ? Colors.green.shade800 : Colors.red.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 👉 Tocar no item abre edição
                    onTap: () => _showAddOrEditDialog(vendedor: v),

                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'editar':
                            _showAddOrEditDialog(vendedor: v);
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
                            leading: Icon(v.ativo ? Icons.visibility_off : Icons.visibility),
                            title:
                            Text(v.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo'),
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
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                );
              },
            ),
          ),
        ),

        // FAB (telas estreitas)
        if (!isWide)
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Align(
              alignment: Alignment.bottomRight,
              child: FloatingActionButton.extended(
                onPressed: () => _showAddOrEditDialog(),
                backgroundColor: milkdimOrange,
                foregroundColor: milkdimWhite,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Adicionar Vendedor'),
                elevation: 3,
              ),
            ),
          ),
      ],
    );
  }
}
