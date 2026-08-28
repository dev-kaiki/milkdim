// lib/tabs/produtos_tab.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import '../services/supabase_service.dart';

const Color milkdimYellow = Color(0xFFFFE066);
const Color milkdimOrange = Color(0xFFE38A1D);
const Color milkdimWhite  = Color(0xFFFFFFFF);
const Color milkdimGrey   = Color(0xFFF7F7F7);

class ProdutosTab extends StatefulWidget {
  const ProdutosTab({super.key});

  @override
  State<ProdutosTab> createState() => _ProdutosTabState();
}

class _ProdutosTabState extends State<ProdutosTab> {
  final _service    = SupabaseService();
  final _searchCtrl = TextEditingController();

  final _brl = NumberFormat.simpleCurrency(locale: 'pt_BR');

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
      final data = await _service.buscarProdutos(); // List<Produto>
      if (!mounted) return;
      data.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      setState(() {
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

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[700] : milkdimOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
    );
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
        backgroundColor: milkdimWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.red),
            const SizedBox(width: 8.0),
            Text('Remover Produto',
                style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('Tem certeza que deseja remover "${p.nome}"?'),
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

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // evita fechar sem querer
      builder: (context) {
        final maxW = MediaQuery.of(context).size.width;
        final dialogW = maxW < 420.0 ? maxW - 32.0 : (maxW < 720.0 ? 420.0 : 520.0);
        final isNarrow = dialogW < 420.0;

        return StatefulBuilder(
          builder: (context, setStateSB) => AlertDialog(
            backgroundColor: milkdimWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            title: Row(
              children: [
                Icon(produto == null ? Icons.add_box : Icons.edit, color: milkdimOrange),
                const SizedBox(width: 6.0),
                Text(
                  produto == null ? 'Novo Produto' : 'Editar Produto',
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
                      // Código + Unidade (responsivo sem LayoutBuilder)
                      isNarrow
                          ? Column(
                        children: [
                          TextFormField(
                            controller: codigoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Código',
                              prefixIcon: Icon(Icons.qr_code_2),
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 10.0),
                          TextFormField(
                            controller: unidadeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Unidade (EX: CX, UN, KG)',
                              prefixIcon: Icon(Icons.straighten),
                              filled: true,
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
                                filled: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: TextFormField(
                              controller: unidadeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Unidade (EX: CX, UN, KG)',
                                prefixIcon: Icon(Icons.straighten),
                                filled: true,
                              ),
                              textCapitalization: TextCapitalization.characters,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10.0),
                      TextFormField(
                        controller: nomeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome *',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          filled: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10.0),
                      TextFormField(
                        controller: precoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Preço *',
                          prefixIcon: Icon(Icons.attach_money),
                          helperText: 'Aceita vírgula ou ponto como separador',
                          filled: true,
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
                      const SizedBox(height: 8.0),
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
                    if (produto == null) {
                      await Supabase.instance.client.from('produtos').insert(map);
                    } else {
                      await Supabase.instance.client.from('produtos').update(map).eq('id', produto.id);
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
                style: FilledButton.styleFrom(backgroundColor: milkdimOrange, foregroundColor: milkdimWhite),
              ),
            ],
          ),
        );
      },
    );

    if (saved == true) {
      _toast(produto == null ? 'Produto adicionado' : 'Produto atualizado');
      await _fetchProdutos();
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 640.0;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 18.0, 16.0, 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                filled: true,
                fillColor: milkdimWhite,
                hintText: 'Buscar por nome, código ou unidade...',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 2.0),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: milkdimYellow, width: 2.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                  borderSide: const BorderSide(color: milkdimOrange, width: 2.2),
                ),
              ),
            ),
          ),
          if (isWide) const SizedBox(width: 12.0),
          if (isWide)
            FilledButton.icon(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
              style: FilledButton.styleFrom(backgroundColor: milkdimOrange, foregroundColor: milkdimWhite),
            ),
        ],
      ),
    );

    final list = _loading
        ? const Center(child: CircularProgressIndicator(color: milkdimOrange))
        : _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
        : _filtered.isEmpty
        ? const Center(
      child: Text('Nenhum produto encontrado.',
          style: TextStyle(color: milkdimOrange, fontSize: 18.0)),
    )
        : RefreshIndicator(
      onRefresh: _fetchProdutos,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4.0),
        itemBuilder: (context, i) {
          final p = _filtered[i];
          return Card(
            color: milkdimWhite,
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 7.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.0)),
            elevation: 2.6,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: p.ativo ? milkdimOrange.withOpacity(.15) : milkdimGrey,
                child: Icon(Icons.inventory_2,
                    color: p.ativo ? milkdimOrange : Colors.grey),
              ),
              title: Text(
                p.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: milkdimOrange, fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Código: ${p.codigo ?? '-'} • Unidade: ${p.unidade ?? '-'}',
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        _brl.format(p.preco),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: p.ativo ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(999.0),
                      border: Border.all(
                        color: p.ativo
                            ? Colors.green.shade300
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      p.ativo ? 'Ativo' : 'Inativo',
                      style: TextStyle(
                        color: p.ativo
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              // 👉 Tocar no item abre edição
              onTap: () => _showAddOrEditDialog(produto: p),

              trailing: PopupMenuButton<String>(
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
                      leading: Icon(p.ativo ? Icons.visibility_off : Icons.visibility),
                      title: Text(p.ativo ? 'Marcar como Inativo' : 'Marcar como Ativo'),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            ),
          );
        },
      ),
    );

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
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              backgroundColor: milkdimOrange,
              foregroundColor: milkdimWhite,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Produto'),
              elevation: 3.0,
            ),
          ),
      ],
    );
  }
}
