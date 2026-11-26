// lib/financeiro/dialogo_categorias.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../services/financeiro_service.dart';
import '../services/supabase_service.dart';
import 'modelos_financeiro.dart';

/// Lista todas as categorias e permite criar, renomear e desativar/reativar.
Future<void> mostrarDialogoCategorias(
    BuildContext context, FonteFinanceiro fonte) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoCategorias(fonte: fonte),
  );
}

class _DialogoCategorias extends StatefulWidget {
  final FonteFinanceiro fonte;
  const _DialogoCategorias({required this.fonte});

  @override
  State<_DialogoCategorias> createState() => _DialogoCategoriasState();
}

class _DialogoCategoriasState extends State<_DialogoCategorias> {
  List<CategoriaSaida> _cats = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  void _erro(Object e) {
    if (!mounted) return;
    final msg = e is RepoFailure ? e.message : 'Erro: $e';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _recarregar() async {
    try {
      final c = await widget.fonte.categorias();
      if (!mounted) return;
      setState(() {
        _cats = c;
        _carregando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
      _erro(e);
    }
  }

  Future<void> _agir(Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      _erro(e);
      return;
    }
    await _recarregar();
  }

  Future<String?> _pedirNome(String titulo, {String inicial = ''}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogoNome(titulo: titulo, inicial: inicial),
    );
  }

  Future<void> _nova() async {
    final nome = await _pedirNome('Nova categoria');
    if (nome == null) return;
    await _agir(() => widget.fonte.criarCategoria(nome));
  }

  Future<void> _renomear(CategoriaSaida c) async {
    final nome = await _pedirNome('Renomear categoria', inicial: c.nome);
    if (nome == null || nome == c.nome) return;
    await _agir(() => widget.fonte.renomearCategoria(c.id, nome));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Categorias'),
      content: SizedBox(
        width: 400,
        child: _carregando
            ? const Padding(
                padding: EdgeInsets.all(MdSpace.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in _cats)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.ativa ? c.nome : '${c.nome} (desativada)',
                              style: c.ativa
                                  ? tt.bodyLarge
                                  : tt.bodyLarge!
                                      .copyWith(color: MdColors.textMuted),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Renomear',
                            onPressed: () => _renomear(c),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: c.ativa ? 'Desativar' : 'Reativar',
                            onPressed: () => _agir(() => widget.fonte
                                .definirCategoriaAtiva(c.id, !c.ativa)),
                            icon: Icon(c.ativa
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _nova,
          icon: const Icon(Icons.add),
          label: const Text('Nova categoria'),
        ),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }
}

class _DialogoNome extends StatefulWidget {
  final String titulo;
  final String inicial;
  const _DialogoNome({required this.titulo, required this.inicial});

  @override
  State<_DialogoNome> createState() => _DialogoNomeState();
}

class _DialogoNomeState extends State<_DialogoNome> {
  late final TextEditingController _c =
      TextEditingController(text: widget.inicial);
  String? _erro;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final n = _c.text.trim();
    if (n.isEmpty) {
      setState(() => _erro = 'Informe o nome.');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Nome', errorText: _erro),
        onSubmitted: (_) => _ok(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('Salvar')),
      ],
    );
  }
}
