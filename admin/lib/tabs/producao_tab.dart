// lib/tabs/producao_tab.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../models/pedido.dart';
import '../models/producao.dart';
import '../services/supabase_service.dart';
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

/// Produção: o que fabricar (total por produto) e os pedidos em aberto, com
/// Finalizar (manual) e Cancelar. Atualiza sozinha a cada [intervalo].
class ProducaoTab extends StatefulWidget {
  /// Pontos de teste; nulos (padrão) usam o [SupabaseService].
  @visibleForTesting
  final Future<List<Pedido>> Function()? carregar;
  @visibleForTesting
  final Future<void> Function(int id)? finalizar;
  @visibleForTesting
  final Future<void> Function(int id)? cancelar;

  final Duration intervalo;

  const ProducaoTab({
    super.key,
    this.carregar,
    this.finalizar,
    this.cancelar,
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
  Future<void> _carregar({bool silencioso = false}) async {
    if (_emVoo) return;
    setState(() => _emVoo = true);
    try {
      final lista = await _buscar();
      if (!mounted) return;
      setState(() {
        _pedidos = lista;
        _erro = null;
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
      }
    }
  }

  // -------------------- ações --------------------

  Future<void> _confirmarFinalizar(Pedido p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: TituloDialogo(
          icone: Icons.check_circle_outline,
          texto: 'Finalizar pedido ${_rotuloNumero(p)}?',
        ),
        content: const Text(
          'Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale a dele.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _executar(
      p,
      widget.finalizar ?? _service.finalizarManual,
      'Pedido finalizado.',
    );
  }

  Future<void> _confirmarCancelar(Pedido p) async {
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
    if (ok != true) return;
    await _executar(
      p,
      widget.cancelar ?? _service.cancelarPedido,
      'Pedido cancelado.',
    );
  }

  Future<void> _executar(
      Pedido p, Future<void> Function(int) acao, String sucesso) async {
    setState(() => _ocupados.add(p.id));
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
    await _carregar(silencioso: true);
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
    final tt = Theme.of(context).textTheme;
    final agora = DateTime.now();
    final vendedor = (p.vendedorNome ?? '').trim().isNotEmpty
        ? p.vendedorNome!.trim()
        : (p.vendedorCodigo ?? '');
    final cliente = (p.clienteNome ?? p.clienteNomeFantasia ?? '—').toString();
    final ocupado = _ocupados.contains(p.id);

    return MdCard(
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
              Text(haTempo(p.enviadoEm, agora),
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
          if (p.alteradoDepoisDeEnviar) ...[
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
                onPressed: ocupado ? null : () => _confirmarFinalizar(p),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Finalizar'),
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

  Widget _listaPedidos() {
    if (_pedidos.isEmpty) {
      return const MdEmptyState(
        icone: Icons.inventory_2_outlined,
        titulo: 'Nenhum pedido em aberto',
        texto: 'Quando um vendedor enviar um pedido, ele aparece aqui.',
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _pedidos.length; i++) ...[
          if (i > 0) const SizedBox(height: MdSpace.md),
          _cartao(_pedidos[i]),
        ],
      ],
    );
  }

  Widget _cabecalhoPedidos() => MdSectionHeader(
        titulo: 'Pedidos em aberto',
        trailing: OutlinedButton.icon(
          onPressed: _emVoo ? null : _carregar,
          icon: _emVoo
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('Atualizar'),
        ),
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
                      children: [erro, _cabecalhoPedidos(), _listaPedidos()],
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
              _cabecalhoPedidos(),
              _listaPedidos(),
            ],
          ),
        );
      },
    );
  }
}
