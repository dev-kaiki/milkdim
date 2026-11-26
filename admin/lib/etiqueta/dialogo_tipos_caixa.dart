// Diálogo "Tipos de caixa": lista, cria e edita (não apaga).
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../services/caixas_service.dart';
import '../services/supabase_service.dart' show RepoFailure;
import '../widgets/lista_adaptavel.dart' show TituloDialogo;
import 'volumes.dart';

Future<void> mostrarDialogoTiposCaixa(BuildContext context, FonteCaixas fonte) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoTiposCaixa(fonte: fonte),
  );
}

String _mensagemDe(Object e) => e is RepoFailure ? e.message : '$e';

class _DialogoTiposCaixa extends StatefulWidget {
  final FonteCaixas fonte;
  const _DialogoTiposCaixa({required this.fonte});

  @override
  State<_DialogoTiposCaixa> createState() => _DialogoTiposCaixaState();
}

class _DialogoTiposCaixaState extends State<_DialogoTiposCaixa> {
  List<TipoCaixa> _tipos = const [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _erro(Object e) {
    if (!mounted) return;
    showMdSnack(context, _mensagemDe(e), tipo: MdTipo.erro);
  }

  Future<void> _carregar() async {
    try {
      final t = await widget.fonte.tiposCaixa();
      if (!mounted) return;
      setState(() {
        _tipos = t;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _erro(e);
    }
  }

  Future<void> _editar([TipoCaixa? tipo]) async {
    final nomeCtrl = TextEditingController(text: tipo?.nome ?? '');
    final capCtrl =
        TextEditingController(text: tipo == null ? '' : '${tipo.capacidade}');
    final formKey = GlobalKey<FormState>();
    var mistura = tipo?.misturaSabores ?? true;
    var ativo = tipo?.ativo ?? true;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: TituloDialogo(
            icone: tipo == null ? Icons.add_box : Icons.edit,
            texto: tipo == null ? 'Novo tipo de caixa' : 'Editar tipo de caixa',
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(labelText: 'Nome *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o nome'
                        : null,
                  ),
                  const SizedBox(height: MdSpace.md),
                  TextFormField(
                    controller: capCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Capacidade (unidades) *'),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n <= 0) ? 'Capacidade inválida.' : null;
                    },
                  ),
                  const SizedBox(height: MdSpace.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Misturar sabores na mesma caixa'),
                    value: mistura,
                    onChanged: (v) => setSB(() => mistura = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    value: ativo,
                    onChanged: (v) => setSB(() => ativo = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final nome = nomeCtrl.text.trim();
                final cap = int.parse(capCtrl.text.trim());
                try {
                  if (tipo == null) {
                    await widget.fonte.criarTipo(nome, cap, mistura);
                  } else {
                    await widget.fonte.alterarTipo(TipoCaixa(
                      id: tipo.id,
                      nome: nome,
                      capacidade: cap,
                      misturaSabores: mistura,
                      ativo: ativo,
                    ));
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (!ctx.mounted) return;
                  showMdSnack(ctx, _mensagemDe(e), tipo: MdTipo.erro);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => _carregando = true);
      await _carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      title: const TituloDialogo(icone: Icons.inventory, texto: 'Tipos de caixa'),
      content: SizedBox(
        width: 420,
        child: _carregando
            ? const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator()))
            : _tipos.isEmpty
                ? const Text('Nenhum tipo de caixa cadastrado.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in _tipos)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t.ativo ? t.nome : '${t.nome} (desativado)',
                            style: tt.bodyLarge!.copyWith(
                                fontWeight: FontWeight.w600,
                                color: t.ativo ? null : MdColors.textMuted),
                          ),
                          subtitle: Text(
                              '${t.capacidade} por caixa • ${t.misturaSabores ? 'mistura sabores' : 'um sabor por caixa'}'),
                          trailing: IconButton(
                            tooltip: 'Editar ${t.nome}',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editar(t),
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Novo tipo'),
          onPressed: () => _editar(),
        ),
      ],
    );
  }
}
