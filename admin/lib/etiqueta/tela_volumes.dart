// Tela "Volumes do pedido": monta, confere e confirma as caixas antes de
// imprimir uma etiqueta por volume.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../models/pedido.dart';
import 'volumes.dart';

/// Abre a tela de volumes. Devolve os volumes confirmados (botão "Imprimir"),
/// ou null se cancelou.
///
/// - [tiposPorNome]: tipos de caixa por [TipoCaixa.nome]; só os ativos podem
///   ser escolhidos em "Nova caixa".
/// - [avisos]: textos de aviso no topo (ex.: pedido mudou depois das caixas).
/// - [somenteLeitura]: só "Imprimir" e "Cancelar".
/// - [sugestao]: volumes para voltar quando se desliga "Pedido solto" e a
///   tela abriu em pedido solto.
Future<VolumesPedido?> mostrarTelaVolumes(
  BuildContext context, {
  required Pedido pedido,
  required VolumesPedido inicial,
  required Map<String, TipoCaixa> tiposPorNome,
  List<String> avisos = const [],
  bool somenteLeitura = false,
  VolumesPedido? sugestao,
}) {
  return Navigator.of(context).push<VolumesPedido>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TelaVolumes(
        pedido: pedido,
        inicial: inicial,
        tiposPorNome: tiposPorNome,
        avisos: avisos,
        somenteLeitura: somenteLeitura,
        sugestao: sugestao,
      ),
    ),
  );
}

class _Linha {
  final String nome;
  final TextEditingController ctrl;
  int quantidade;
  _Linha(this.nome, this.quantidade)
      : ctrl = TextEditingController(text: '$quantidade');
}

class _Vol {
  final bool caixa;
  final String? tipoNome;
  final List<_Linha> linhas;
  _Vol(this.caixa, this.tipoNome, this.linhas);

  factory _Vol.de(Volume v) => _Vol(v.caixa, v.tipoNome,
      [for (final i in v.itens) _Linha(i.nome, i.quantidade)]);

  Volume paraVolume() => Volume(
        caixa: caixa,
        tipoNome: tipoNome,
        itens: [
          for (final l in linhas) ItemVolume(nome: l.nome, quantidade: l.quantidade)
        ],
      );
}

class TelaVolumes extends StatefulWidget {
  final Pedido pedido;
  final VolumesPedido inicial;
  final Map<String, TipoCaixa> tiposPorNome;
  final List<String> avisos;
  final bool somenteLeitura;
  final VolumesPedido? sugestao;

  const TelaVolumes({
    super.key,
    required this.pedido,
    required this.inicial,
    required this.tiposPorNome,
    this.avisos = const [],
    this.somenteLeitura = false,
    this.sugestao,
  });

  @override
  State<TelaVolumes> createState() => _TelaVolumesState();
}

class _TelaVolumesState extends State<TelaVolumes> {
  late bool _solto = widget.inicial.solto;
  late List<_Vol> _vols = _de(widget.inicial);
  // Montagem anterior ao "Pedido solto", para voltar sem perder a edição.
  List<_Vol>? _guardado;

  List<_Vol> _de(VolumesPedido v) => [for (final x in v.volumes) _Vol.de(x)];

  // Controladores só são liberados no dispose: um campo removido ainda está
  // montado até o fim do quadro.
  final List<TextEditingController> _lixo = [];

  void _descartar(List<_Vol> l) {
    for (final v in l) {
      _lixo.addAll(v.linhas.map((i) => i.ctrl));
    }
  }

  @override
  void dispose() {
    _descartar(_vols);
    if (_guardado != null) _descartar(_guardado!);
    for (final c in _lixo) {
      c.dispose();
    }
    super.dispose();
  }

  /// Avulsos sem nenhuma linha não vira volume: some do resultado e a
  /// numeração das caixas se recalcula.
  bool _fora(_Vol v) => !_solto && !v.caixa && v.linhas.isEmpty;

  VolumesPedido get _atual => VolumesPedido(
        solto: _solto,
        volumes: [
          for (final v in _vols)
            if (!_fora(v)) v.paraVolume()
        ],
      );

  /// Nomes do pedido, um por produto (trim), na ordem do pedido.
  List<String> get _produtosDoPedido {
    final vistos = <String>{};
    final out = <String>[];
    for (final i in widget.pedido.itens) {
      final k = i.nome.trim();
      if (vistos.add(k)) out.add(i.nome);
    }
    return out;
  }

  List<TipoCaixa> get _tiposAtivos =>
      widget.tiposPorNome.values.where((t) => t.ativo).toList();

  void _alternarSolto(bool v) {
    setState(() {
      if (v) {
        _guardado = _vols;
        _vols = _de(pedidoSolto(widget.pedido.itens));
      } else {
        _descartar(_vols);
        _vols = _guardado ??
            _de(widget.sugestao ??
                VolumesPedido(
                    solto: false,
                    volumes: pedidoSolto(widget.pedido.itens).volumes));
        _guardado = null;
      }
      _solto = v;
    });
  }

  Future<void> _novaCaixa() async {
    final tipos = _tiposAtivos;
    if (tipos.isEmpty) return;
    TipoCaixa? t = tipos.length == 1 ? tipos.first : null;
    if (t == null) {
      t = await showDialog<TipoCaixa>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Tipo da caixa'),
          children: [
            for (final x in tipos)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(x),
                child: Text('${x.nome} (cabem ${x.capacidade})'),
              ),
          ],
        ),
      );
      if (t == null || !mounted) return;
    }
    setState(() {
      // Caixas ficam antes dos avulsos.
      var pos = _vols.length;
      while (pos > 0 && !_vols[pos - 1].caixa) {
        pos--;
      }
      _vols.insert(pos, _Vol(true, t!.nome, []));
    });
  }

  void _novoAvulso() {
    setState(() {
      if (!_vols.any((v) => !v.caixa)) _vols.add(_Vol(false, null, []));
    });
  }

  void _apagarVolume(int i) {
    setState(() {
      final v = _vols.removeAt(i);
      _descartar([v]);
    });
  }

  Future<void> _adicionarProduto(int i) async {
    final nomes = _produtosDoPedido;
    if (nomes.isEmpty) return;
    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Adicionar produto'),
        children: [
          for (final n in nomes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(n),
              child: Text(n),
            ),
        ],
      ),
    );
    if (nome == null || !mounted) return;
    setState(() {
      final v = _vols[i];
      final existente =
          v.linhas.where((l) => l.nome.trim() == nome.trim()).firstOrNull;
      if (existente != null) {
        existente.quantidade += 1;
        existente.ctrl.text = '${existente.quantidade}';
      } else {
        v.linhas.add(_Linha(nome, 1));
      }
    });
  }

  void _removerLinha(int i, _Linha l) {
    setState(() {
      _vols[i].linhas.remove(l);
      _lixo.add(l.ctrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final atual = _atual;
    final conferencia = conferirVolumes(widget.pedido.itens, atual);
    // Posição de cada cartão em [atual]; null = avulsos vazio (fora).
    final pos = <int?>[];
    var n = 0;
    for (final v in _vols) {
      pos.add(_fora(v) ? null : n++);
    }
    // O servidor recusa quantidade <= 0: bloqueia aqui também.
    final invalidas = [
      for (var i = 0; i < _vols.length; i++)
        if (pos[i] != null)
          for (final l in _vols[i].linhas)
            if (l.quantidade <= 0)
              '${rotuloVolume(atual, pos[i]!)}: ${l.nome.trim()} precisa de quantidade maior que zero',
    ];
    final erros = [...conferencia, ...invalidas];
    final avisos = avisosCapacidade(atual, widget.tiposPorNome);
    final editavel = !widget.somenteLeitura && !_solto;
    final numero = (widget.pedido.numero ?? '').trim().isNotEmpty
        ? widget.pedido.numero!.trim()
        : '${widget.pedido.id}';
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('Volumes do pedido $numero')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(MdSpace.lg),
                children: [
                  for (final a in widget.avisos) ...[
                    MdBanner(tipo: MdTipo.atencao, texto: a),
                    const SizedBox(height: MdSpace.md),
                  ],
                  for (final e in erros) ...[
                    MdBanner(tipo: MdTipo.erro, texto: e),
                    const SizedBox(height: MdSpace.sm),
                  ],
                  for (final a in avisos) ...[
                    MdBanner(tipo: MdTipo.atencao, texto: a),
                    const SizedBox(height: MdSpace.sm),
                  ],
                  if (erros.isNotEmpty || avisos.isNotEmpty)
                    const SizedBox(height: MdSpace.sm),
                  if (!widget.somenteLeitura)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pedido solto (sem caixas)'),
                      value: _solto,
                      onChanged: _alternarSolto,
                    ),
                  for (var i = 0; i < _vols.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MdSpace.md),
                      child: MdCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                    pos[i] == null
                                        ? 'Avulsos (vazio)'
                                        : rotuloVolume(atual, pos[i]!),
                                    style: tt.titleMedium),
                                if (editavel)
                                  TextButton.icon(
                                    onPressed: () => _apagarVolume(i),
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(_vols[i].caixa
                                        ? 'Apagar caixa'
                                        : 'Apagar'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: MdSpace.sm),
                            for (final l in _vols[i].linhas)
                              _linha(i, l, editavel),
                            if (editavel)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _adicionarProduto(i),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Adicionar produto'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (editavel)
                    Wrap(
                      spacing: MdSpace.sm,
                      runSpacing: MdSpace.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _tiposAtivos.isEmpty ? null : _novaCaixa,
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Nova caixa'),
                        ),
                        if (!_vols.any((v) => !v.caixa))
                          OutlinedButton.icon(
                            onPressed: _novoAvulso,
                            icon: const Icon(Icons.add),
                            label: const Text('Avulsos'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MdSpace.lg, MdSpace.sm, MdSpace.lg, MdSpace.lg),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MdSpace.sm,
                runSpacing: MdSpace.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: erros.isEmpty
                        ? () => Navigator.of(context).pop(atual)
                        : null,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linha(int i, _Linha l, bool editavel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MdSpace.xs),
      child: Row(
        children: [
          Expanded(child: Text(l.nome.trim())),
          const SizedBox(width: MdSpace.sm),
          if (editavel) ...[
            SizedBox(
              width: 72,
              child: TextField(
                key: ValueKey('qtd-$i-${l.nome.trim()}'),
                controller: l.ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: MdSpace.sm, vertical: MdSpace.sm),
                ),
                onChanged: (t) =>
                    setState(() => l.quantidade = int.tryParse(t) ?? 0),
              ),
            ),
            IconButton(
              tooltip: 'Remover ${l.nome.trim()}',
              onPressed: () => _removerLinha(i, l),
              icon: const Icon(Icons.close),
            ),
          ] else
            Text('${l.quantidade}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
