// lib/financeiro/dialogo_saida.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'modelos_financeiro.dart';

/// Recusa data depois de `hoje + 365 dias`; null quando aceita.
String? validarDataSaida(DateTime data, DateTime hoje) {
  final limite = DateTime(hoje.year, hoje.month, hoje.day + 365);
  final d = DateTime(data.year, data.month, data.day);
  return d.isAfter(limite) ? 'Data muito no futuro.' : null;
}

String _dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _valorEditavel(int centavos) {
  final reais = centavos ~/ 100;
  final cent = (centavos % 100).toString().padLeft(2, '0');
  return '$reais,$cent';
}

/// Diálogo de lançar/editar saída. Devolve a saída preenchida ou null.
Future<Saida?> mostrarDialogoSaida(
  BuildContext context, {
  required List<CategoriaSaida> categorias,
  Saida? editar,
  required DateTime hoje,
}) {
  return showDialog<Saida>(
    context: context,
    builder: (_) =>
        _DialogoSaida(categorias: categorias, editar: editar, hoje: hoje),
  );
}

class _DialogoSaida extends StatefulWidget {
  final List<CategoriaSaida> categorias;
  final Saida? editar;
  final DateTime hoje;
  const _DialogoSaida(
      {required this.categorias, required this.editar, required this.hoje});

  @override
  State<_DialogoSaida> createState() => _DialogoSaidaState();
}

class _DialogoSaidaState extends State<_DialogoSaida> {
  late final TextEditingController _valor = TextEditingController(
      text: widget.editar == null
          ? ''
          : _valorEditavel(widget.editar!.valorCentavos));
  late final TextEditingController _descricao =
      TextEditingController(text: widget.editar?.descricao ?? '');
  late DateTime _data = widget.editar?.data ??
      DateTime(widget.hoje.year, widget.hoje.month, widget.hoje.day);
  int? _categoriaId;
  String? _erroValor;
  String? _erroCategoria;
  String? _erroData;

  @override
  void initState() {
    super.initState();
    _categoriaId = widget.editar?.categoriaId;
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    super.dispose();
  }

  /// Ativas, mais a categoria atual da saída em edição (mesmo desativada).
  List<CategoriaSaida> get _opcoes => [
        for (final c in widget.categorias)
          if (c.ativa || c.id == widget.editar?.categoriaId) c,
      ];

  Future<void> _escolherData() async {
    final base = DateTime(widget.hoje.year, widget.hoje.month, widget.hoje.day);
    final p = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(base.year, base.month, base.day + 365),
    );
    if (p != null) setState(() => _data = p);
  }

  void _salvar() {
    final cent = parseValorCentavos(_valor.text);
    final erroData = validarDataSaida(_data, widget.hoje);
    setState(() {
      _erroValor = cent == null ? 'Valor inválido.' : null;
      _erroCategoria = _categoriaId == null ? 'Escolha a categoria.' : null;
      _erroData = erroData;
    });
    if (cent == null || _categoriaId == null || erroData != null) return;
    Navigator.pop(
      context,
      Saida(
        id: widget.editar?.id,
        data: _data,
        categoriaId: _categoriaId!,
        descricao: _descricao.text.trim(),
        valorCentavos: cent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.editar == null ? 'Lançar saída' : 'Editar saída'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _categoriaId,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: 'Categoria', errorText: _erroCategoria),
                items: [
                  for (final c in _opcoes)
                    DropdownMenuItem(value: c.id, child: Text(c.nome)),
                ],
                onChanged: (v) => setState(() {
                  _categoriaId = v;
                  _erroCategoria = null;
                }),
              ),
              const SizedBox(height: MdSpace.md),
              TextField(
                controller: _valor,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'Valor', errorText: _erroValor),
              ),
              const SizedBox(height: MdSpace.md),
              TextField(
                controller: _descricao,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: MdSpace.md),
              OutlinedButton.icon(
                onPressed: _escolherData,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Data: ${_dataBr(_data)}'),
              ),
              if (_erroData != null)
                Padding(
                  padding: const EdgeInsets.only(top: MdSpace.xs),
                  child: Text(_erroData!,
                      style: tt.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
