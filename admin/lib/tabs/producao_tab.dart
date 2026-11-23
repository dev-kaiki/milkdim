// lib/tabs/producao_tab.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../models/pedido.dart';
import '../models/producao.dart';
import '../services/supabase_service.dart';
import '../widgets/detalhe_pedido.dart';
import '../widgets/lista_adaptavel.dart';

/// Largura a partir da qual os totais ficam ao lado da lista de pedidos.
const double _larguraLado = 900;

/// "há 3 h", "há 12 min", "há 2 dias": tempo desde [desde] até [agora].
String haTempo(DateTime? desde, DateTime agora) {
  if (desde == null) return '—';
  final d = agora.difference(desde);
  if (d.inMinutes < 1) return 'agora há pouco';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  final dias = d.inDays;
  return dias == 1 ? 'há 1 dia' : 'há $dias dias';
}

/// Produção: o que fabricar (total por produto), os pedidos em aberto (com
/// "Produção concluída" e Cancelar) e os prontos para entrega (com "Marcar
/// como entregue" e Cancelar). Atualiza sozinha a cada [intervalo].
class ProducaoTab extends StatefulWidget {
  /// Pontos de teste; nulos (padrão) usam o [SupabaseService].
  @visibleForTesting
  final Future<List<Pedido>> Function()? carregar;
  /// Recebe o id e o `alterado_em` bruto da linha (para o servidor conferir).
  @visibleForTesting
  final Future<void> Function(int id, String? alteradoEmBruto)? marcarPronto;
  @visibleForTesting
  final Future<void> Function(int id)? finalizar;
  @visibleForTesting
  final Future<void> Function(int id)? cancelar;

  /// Busca do detalhe ao tocar no pedido; nulo usa [buscarDetalhePedido].
  @visibleForTesting
  final Future<DetalheDoPedido> Function(int id)? buscarDetalhe;

  final Duration intervalo;

  const ProducaoTab({
    super.key,
    this.carregar,
    this.marcarPronto,
    this.finalizar,
    this.cancelar,
    this.buscarDetalhe,
    this.intervalo = const Duration(seconds: 30),
  });

  @override
  State<ProducaoTab> createState() => _ProducaoTabState();
}

class _ProducaoTabState extends State<ProducaoTab> {
  late final _service = SupabaseService();
  final _horaFmt = DateFormat('HH:mm');

  Timer? _timer;
  bool _primeiraCarga = true;
  bool _emVoo = false;
  bool _recarregarDepois = false;
  DateTime? _atualizadoEm;
  List<Pedido> _pedidos = [];
  String? _erro;
  final Set<int> _ocupados = {};

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(widget.intervalo, (_) {
      if (!mounted) return;
      _carregar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<Pedido>> _buscar() =>
      (widget.carregar ?? _service.buscarPedidosEmAberto)();

  /// Recarrega a lista. Pula se já houver uma carga em andamento.
  /// [silencioso] (timer): não mostra aviso de erro, mantém a lista anterior.
  /// [garantir] (após Finalizar/Cancelar): se já houver carga em andamento,
  /// faz mais uma assim que ela terminar, para a lista não ficar velha.
  Future<void> _carregar({bool silencioso = false, bool garantir = false}) async {
    if (_emVoo) {
      if (garantir) _recarregarDepois = true;
      return;
    }
    setState(() => _emVoo = true);
    try {
      final lista = await _buscar();
      if (!mounted) return;
      setState(() {
        _pedidos = lista;
        _erro = null;
        _atualizadoEm = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is RepoFailure ? e.message : 'Erro ao carregar pedidos em aberto: $e';
      setState(() => _erro = msg);
      if (!silencioso) showMdSnack(context, msg, tipo: MdTipo.erro);
    } finally {
      if (mounted) {
        setState(() {
          _emVoo = false;
          _primeiraCarga = false;
        });
        if (_recarregarDepois) {
          _recarregarDepois = false;
          unawaited(_carregar(silencioso: true));
        }
      }
    }
  }

  // -------------------- ações --------------------

  Future<void> _confirmarPronto(Pedido p) async {
    if (_ocupados.contains(p.id)) return;
    setState(() => _ocupados.add(p.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const TituloDialogo(
          icone: Icons.inventory_2_outlined,
          texto: 'Marcar como pronto para entrega?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _ocupados.remove(p.id));
      return;
    }
    await _executar(
      p,
      (id) => widget.marcarPronto != null
          ? widget.marcarPronto!(id, p.alteradoEmBruto)
          : _service.marcarPronto(id, alteradoEmBruto: p.alteradoEmBruto),
      'Pedido pronto para entrega.',
    );
  }

  Future<void> _confirmarEntregue(Pedido p) async {
    if (_ocupados.contains(p.id)) return;
    setState(() => _ocupados.add(p.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: TituloDialogo(
          icone: Icons.check_circle_outline,
          texto: 'Marcar pedido ${_rotuloNumero(p)} como entregue?',
        ),
        content: const Text(
          'Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale a dele.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Marcar como entregue'),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _ocupados.remove(p.id));
      return;
    }
    await _executar(
      p,
      widget.finalizar ?? _service.finalizarManual,
      'Pedido marcado como entregue.',
    );
  }

  Future<void> _confirmarCancelar(Pedido p) async {
    if (_ocupados.contains(p.id)) return;
    setState(() => _ocupados.add(p.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: TituloDialogo(
          icone: Icons.cancel_outlined,
          texto: 'Cancelar pedido ${_rotuloNumero(p)}?',
          destrutivo: true,
        ),
        content: const Text(
          'O pedido sai da produção e não conta mais nos totais a fabricar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          BotaoDestrutivo(texto: 'Cancelar pedido', onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _ocupados.remove(p.id));
      return;
    }
    await _executar(
      p,
      widget.cancelar ?? _service.cancelarPedido,
      'Pedido cancelado.',
    );
  }

  Future<void> _executar(
      Pedido p, Future<void> Function(int) acao, String sucesso) async {
    // O id já foi marcado como ocupado ao abrir a confirmação.
    try {
      await acao(p.id);
      if (!mounted) return;
      showMdSnack(context, sucesso, tipo: MdTipo.sucesso);
    } catch (e) {
      if (!mounted) return;
      final msg = e is RepoFailure ? e.message : 'Erro ao atualizar pedido: $e';
      showMdSnack(context, msg, tipo: MdTipo.erro);
    } finally {
      if (mounted) setState(() => _ocupados.remove(p.id));
    }
    if (!mounted) return;
    await _carregar(silencioso: true, garantir: true);
  }

  // -------------------- helpers --------------------

  String _rotuloNumero(Pedido p) {
    final n = (p.numero ?? '').trim();
    return '#${n.isEmpty ? p.id : n}';
  }

  String _itensResumo(Pedido p) {
    if (p.itens.isEmpty) return 'Sem itens';
    return p.itens.map((i) => '${i.quantidade}× ${i.nome.trim()}').join(', ');
  }

  // -------------------- UI --------------------

  Widget _totais() {
    final totais = totaisAFabricar(_pedidos);
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MdSectionHeader(titulo: 'A fabricar'),
        if (totais.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
            child: Text('Nada a fabricar no momento.',
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          )
        else
          MdCard(
            padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg, vertical: MdSpace.sm),
            child: Column(
              children: [
                for (var i = 0; i < totais.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: MdSpace.md),
                    child: Row(
                      children: [
                        Expanded(child: Text(totais[i].nome, style: tt.bodyLarge)),
                        const SizedBox(width: MdSpace.md),
                        Text('${totais[i].quantidade}',
                            style: tt.titleLarge!.copyWith(color: MdColors.primaryStrong)),
                        const SizedBox(width: MdSpace.xs),
                        Text('un', style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _cartao(Pedido p) {
    final pronto = p.status == 'pronto';
    final tt = Theme.of(context).textTheme;
    final agora = DateTime.now();
    final vendedor = (p.vendedorNome ?? '').trim().isNotEmpty
        ? p.vendedorNome!.trim()
        : (p.vendedorCodigo ?? '');
    final cliente = (p.clienteNome ?? p.clienteNomeFantasia ?? '—').toString();
    final ocupado = _ocupados.contains(p.id);

    // Tocar abre o mesmo detalhe da aba Pedidos (sem "Apagar": pedido em
    // aberto se cancela, não se apaga).
    return MdCard(
      onTap: () => abrirDetalhesPedido(context, p, buscar: widget.buscarDetalhe),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Pedido ${_rotuloNumero(p)}',
                    style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: MdSpace.sm),
              Text(pronto ? 'pronto ${haTempo(p.prontoEm, agora)}' : haTempo(p.enviadoEm, agora),
                  style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
            ],
          ),
          const SizedBox(height: MdSpace.xs),
          Text(cliente,
              style: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (vendedor.isNotEmpty) ...[
            const SizedBox(height: MdSpace.xs),
            LinhaInfo(icone: Icons.badge_outlined, texto: vendedor),
          ],
          const SizedBox(height: MdSpace.sm),
          Text(_itensResumo(p), style: tt.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (!pronto && p.alteradoDepoisDePronto) ...[
            const SizedBox(height: MdSpace.sm),
            const MdStatusChip(
              tipo: MdTipo.atencao,
              icone: Icons.edit_outlined,
              texto: 'alterado depois de pronto',
            ),
          ] else if (!pronto && p.alteradoDepoisDeEnviar) ...[
            const SizedBox(height: MdSpace.sm),
            MdStatusChip(
              tipo: MdTipo.atencao,
              icone: Icons.edit_outlined,
              texto: 'alterado às ${_horaFmt.format(p.alteradoEm!.toLocal())}',
            ),
          ],
          const SizedBox(height: MdSpace.md),
          Wrap(
            spacing: MdSpace.md,
            runSpacing: MdSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: ocupado
                    ? null
                    : () => pronto ? _confirmarEntregue(p) : _confirmarPronto(p),
                icon: Icon(pronto ? Icons.local_shipping_outlined : Icons.check_rounded),
                label: Text(pronto ? 'Marcar como entregue' : 'Produção concluída'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MdColors.danger,
                  side: const BorderSide(color: MdColors.danger),
                ),
                onPressed: ocupado ? null : () => _confirmarCancelar(p),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lista(List<Pedido> pedidos, {required String vazioTitulo, required String vazioTexto}) {
    if (pedidos.isEmpty) {
      return MdEmptyState(
        icone: Icons.inventory_2_outlined,
        titulo: vazioTitulo,
        texto: vazioTexto,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < pedidos.length; i++) ...[
          if (i > 0) const SizedBox(height: MdSpace.md),
          _cartao(pedidos[i]),
        ],
      ],
    );
  }

  List<Pedido> get _abertos => _pedidos.where((p) => p.status == 'salvo').toList();
  List<Pedido> get _prontos => _pedidos.where((p) => p.status == 'pronto').toList();

  /// As duas seções: pedidos em aberto e prontos para entrega.
  List<Widget> _secoes() => [
        _cabecalhoPedidos(),
        _lista(_abertos,
            vazioTitulo: 'Nenhum pedido em aberto',
            vazioTexto: 'Quando um vendedor enviar um pedido, ele aparece aqui.'),
        const SizedBox(height: MdSpace.lg),
        const MdSectionHeader(titulo: 'Prontos para entrega'),
        _lista(_prontos,
            vazioTitulo: 'Nenhum pedido pronto',
            vazioTexto: 'Quando a produção concluir um pedido, ele aparece aqui.'),
      ];

  Widget _cabecalhoPedidos() => MdSectionHeader(
        titulo: 'Pedidos em aberto',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_atualizadoEm != null)
              Padding(
                padding: const EdgeInsets.only(right: MdSpace.md),
                child: Text(
                  'Atualizado às ${_horaFmt.format(_atualizadoEm!.toLocal())}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: MdColors.textMuted),
                ),
              ),
            _botaoAtualizar(),
          ],
        ),
      );

  Widget _botaoAtualizar() => OutlinedButton.icon(
          onPressed: _emVoo ? null : _carregar,
          icon: _emVoo
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('Atualizar'),
        );

  @override
  Widget build(BuildContext context) {
    if (_primeiraCarga) return const Center(child: CircularProgressIndicator());

    final Widget erro = _erro == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: MdSpace.md),
            child: MdBanner(tipo: MdTipo.erro, texto: _erro!),
          );

    return LayoutBuilder(
      builder: (context, c) {
        const padding = EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.sm, MdSpace.lg, MdSpace.lg);
        if (c.maxWidth >= _larguraLado) {
          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(child: _totais()),
                ),
                const SizedBox(width: MdSpace.xl),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _carregar,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [erro, ..._secoes()],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              erro,
              _totais(),
              const SizedBox(height: MdSpace.lg),
              ..._secoes(),
            ],
          ),
        );
      },
    );
  }
}
