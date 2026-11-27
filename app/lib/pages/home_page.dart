// lib/pages/home_page.dart
//
// • Ao abrir: se a última sync completa tem 7 dias ou mais, sincroniza (com
//   internet) ou só avisa (sem internet) — nunca impede o vendedor de trabalhar.
//   Com internet e sync em dia, tenta subir os pedidos aguardando envio.
// • Mostra "N pedidos aguardando envio" com o botão "Enviar agora".
// • "Sair" fica bloqueado enquanto houver pedido aguardando envio. A volta para
//   o login é feita pelo listener de sessão do main.dart.
// • "Meus pedidos" passa o vendedorCodigo para filtrar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/auth.dart';
import '../utils/db.dart';
import '../utils/supabase_helper.dart';
import 'pedido_page.dart';
import 'pedidos_page.dart';
import '../utils/clientes_sumidos.dart';
import 'clientes_sumidos_page.dart';
import 'entregas_page.dart';
import '../utils/minhas_vendas.dart';
import 'minhas_vendas_page.dart';
import '../utils/entregas.dart';
import 'configuracoes_page.dart';
import 'ler_etiqueta_page.dart';
import '../widgets/ouvir_etiqueta_pendente.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Só para a captura visual: quando informado, mostra este número de
  /// pendentes e não roda a rotina de abertura (SQLite, rede e sync).
  final int? pendentesParaCaptura;

  /// Só para a captura visual e testes: contagem de clientes sumidos. Sem ela,
  /// o item só aparece depois de calcular no banco (e nunca na captura).
  final int? sumidosParaCaptura;

  /// Só para a captura visual e testes: contagem de pedidos prontos para entregar.
  final int? prontosParaCaptura;

  /// Só para a captura visual e testes: vendido no mês atual (R$).
  final double? vendasParaCaptura;

  const HomePage({
    super.key,
    required this.vendedor,
    this.pendentesParaCaptura,
    this.sumidosParaCaptura,
    this.prontosParaCaptura,
    this.vendasParaCaptura,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _pendentes = 0;

  /// Clientes sem comprar há 30 dias ou mais; null enquanto não calculou.
  int? _sumidos;

  /// Pedidos prontos para entregar; null enquanto não calculou.
  int? _prontos;

  /// Vendido e o mês a que o valor se refere; null enquanto não calculou.
  /// Guarda o mês junto para nunca misturar o total de um mês com o nome de outro.
  ({double valor, int ano, int mes})? _vendas;
  bool _sincronizando = false;
  bool _enviando = false;

  /// Só para o selo do cartão: null enquanto não se sabe, true se a última
  /// sync completa tem menos de 7 dias.
  bool? _syncEmDia;

  String get _codigo => widget.vendedor['codigo']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final captura = widget.pendentesParaCaptura;
    if (captura != null) {
      _pendentes = captura;
      _sumidos = widget.sumidosParaCaptura;
      _prontos = widget.prontosParaCaptura;
      final v = widget.vendasParaCaptura;
      if (v != null) {
        final agora = DateTime.now();
        _vendas = (valor: v, ano: agora.year, mes: agora.month);
      }
      _syncEmDia = true;
      return;
    }
    _aoAbrir();
  }

  Future<void> _aoAbrir() async {
    await _atualizarPendentes();
    if (_codigo.isEmpty) return;
    final online = await temInternet();
    final vencida = await syncVencida();
    if (!mounted) return;
    setState(() => _syncEmDia = !vencida);
    if (vencida) {
      if (online) {
        await _sincronizar();
      } else {
        await _avisarSyncVencidaOffline();
      }
    } else if (online) {
      await _enviarPendentes(silencioso: true);
    }
  }

  Future<void> _atualizarSumidos() async {
    if (_codigo.isEmpty) return;
    try {
      final clientes = await listarClientes();
      final pedidos = await listarPedidosParaSumidos(_codigo);
      final n = clientesSumidos(
        clientes: clientes,
        pedidos: pedidos,
        vendedorCodigo: _codigo,
        agora: DateTime.now(),
        prazoDias: kPrazosSumido.first,
      ).length;
      if (mounted) setState(() => _sumidos = n);
    } catch (e) {
      debugPrint('Erro ao contar clientes sumidos: $e');
    }
  }

  Future<void> _atualizarProntos() async {
    if (_codigo.isEmpty) return;
    try {
      final pedidos = await listarPedidosProntos(_codigo);
      final n = contarProntos(pedidos, vendedorCodigo: _codigo);
      if (mounted) setState(() => _prontos = n);
    } catch (e) {
      debugPrint('Erro ao contar entregas prontas: $e');
    }
  }

  /// Só mostra o valor se for do mês atual; senão volta ao texto neutro.
  String _subtituloVendas() {
    final agora = DateTime.now();
    final v = _vendas;
    final atual = v != null && v.ano == agora.year && v.mes == agora.month;
    return subtituloVendas(atual ? v.valor : null, agora.month);
  }

  Future<void> _atualizarVendas() async {
    if (_codigo.isEmpty) return;
    try {
      final agora = DateTime.now();
      final pedidos = await listarVendasDoMesParaHome(
          _codigo, DateTime(agora.year, agora.month, 1).toUtc());
      final v = vendidoNoMes(pedidos,
          vendedorCodigo: _codigo, ano: agora.year, mes: agora.month);
      if (mounted) setState(() => _vendas = (valor: v, ano: agora.year, mes: agora.month));
    } catch (e) {
      debugPrint('Erro ao somar as vendas do mês: $e');
    }
  }

  Future<void> _atualizarPendentes() async {
    if (_codigo.isEmpty) return;
    unawaited(_atualizarSumidos());
    unawaited(_atualizarProntos());
    unawaited(_atualizarVendas());
    try {
      final n = await contarPedidosPendentesEnvio(_codigo);
      if (mounted) setState(() => _pendentes = n);
    } catch (e) {
      debugPrint('Erro ao contar pendentes: $e');
    }
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    var ok = false;
    try {
      ok = await sincronizarTudoERegistrar(vendedorCodigo: _codigo);
    } catch (e) {
      debugPrint('Erro na sincronização: $e');
    }
    if (!mounted) return;
    setState(() {
      _sincronizando = false;
      if (ok) _syncEmDia = true;
    });
    _showSnack(
      ok ? 'Sincronização realizada!' : 'Erro ao sincronizar dados.',
      sucesso: ok,
    );
    await _atualizarPendentes();
  }

  Future<void> _avisarSyncVencidaOffline() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_off_outlined, color: MdColors.warning, size: 32),
        title: const Text('Sincronização atrasada'),
        content: const Text(
          'Faz 7 dias ou mais sem sincronizar.\n\n'
          'Você pode continuar trabalhando, mas conecte à internet assim que puder '
          'para atualizar clientes, produtos e pedidos.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarPendentes({bool silencioso = false}) async {
    if (_enviando || _codigo.isEmpty) return;
    setState(() => _enviando = true);
    ({int enviados, int falhas, int numeroEmUso, int apagados})? r;
    try {
      r = await subirPedidosPendentes(vendedorCodigo: _codigo);
    } catch (e) {
      debugPrint('Erro ao enviar pendentes: $e');
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    await _atualizarPendentes();
    if (!mounted || silencioso) return;
    if (r == null || r.falhas > 0) {
      _showSnack('Não foi possível enviar todos os pedidos. Verifique a internet.',
          sucesso: false);
    } else if (r.enviados > 0) {
      _showSnack('Pedidos enviados!');
    }
  }

  Future<void> _sair() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Para entrar de novo será preciso internet. Deseja sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await sair();
      // O listener de sessão do main.dart leva para o login.
    } on LoginRecusado catch (e) {
      _showSnack(e.mensagem, sucesso: false);
      await _atualizarPendentes();
    } catch (e) {
      // Offline o signOut remoto falha, mas a sessão local já foi encerrada.
      if (Supabase.instance.client.auth.currentSession != null) {
        _showSnack('Não foi possível sair. Tente de novo.', sucesso: false);
      }
    }
  }

  Future<void> _abrir(Widget pagina) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
    await _atualizarPendentes();
  }

  void _showSnack(String msg, {bool sucesso = true}) {
    if (!mounted) return;
    showMdSnack(context, msg, tipo: sucesso ? MdTipo.sucesso : MdTipo.erro);
  }

  Widget? _seloSync() {
    if (_sincronizando) {
      return const MdStatusChip(tipo: MdTipo.info, texto: 'Sincronizando', icone: Icons.sync);
    }
    return switch (_syncEmDia) {
      true => const MdStatusChip(
          tipo: MdTipo.sucesso, texto: 'Em dia', icone: Icons.cloud_done_outlined),
      false => const MdStatusChip(
          tipo: MdTipo.atencao, texto: 'Desatualizado', icone: Icons.cloud_off_outlined),
      null => null,
    };
  }

  Widget _saudacao(TextTheme tt) {
    final nome = widget.vendedor['nome']?.toString().trim() ?? '';
    final selo = _seloSync();
    return MdCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome.isEmpty ? 'Olá!' : 'Olá, $nome',
                  style: tt.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_codigo.isNotEmpty) ...[
                  const SizedBox(height: MdSpace.xs),
                  Text(
                    'Vendedor $_codigo',
                    style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (selo != null) ...[const SizedBox(width: MdSpace.sm), selo],
        ],
      ),
    );
  }

  Widget _avisoPendentes() {
    final texto = _pendentes == 1
        ? '1 pedido aguardando envio'
        : '$_pendentes pedidos aguardando envio';
    return MdBanner(
      tipo: MdTipo.atencao,
      icone: Icons.cloud_upload_outlined,
      texto: texto,
      acao: _enviando
          ? const Padding(
              padding: EdgeInsets.all(MdSpace.md),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          : TextButton(
              onPressed: _sincronizando ? null : () => _enviarPendentes(),
              child: const Text('Enviar agora'),
            ),
    );
  }

  Widget _linhaSincronizando(TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(MdSpace.xs),
          child: const LinearProgressIndicator(minHeight: 6),
        ),
        const SizedBox(height: MdSpace.sm),
        Text(
          'Sincronizando dados…',
          style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Etiqueta lida pela câmera do celular, fora do app: abre o pedido daqui.
  @override
  Widget build(BuildContext context) =>
      OuvirEtiquetaPendente(vendedorCodigo: _codigo, child: Builder(builder: _tela));

  Widget _tela(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const MdLogoTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _abrir(const ConfiguracoesPage()),
            tooltip: 'Configurações',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _sair,
            tooltip: 'Sair',
          ),
          const SizedBox(width: MdSpace.xs),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.lg, MdSpace.lg, 0),
              sliver: SliverToBoxAdapter(
                child: MdContentWidth(
                  maxWidth: 640,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _saudacao(tt),
                      if (_pendentes > 0) ...[
                        const SizedBox(height: MdSpace.md),
                        _avisoPendentes(),
                      ],
                      const SizedBox(height: MdSpace.xl),
                      MdActionTile(
                        icone: Icons.add_shopping_cart,
                        titulo: 'Novo pedido',
                        subtitulo: 'Escolher cliente e produtos',
                        destaque: true,
                        onTap: () => _abrir(PedidoPage(vendedor: widget.vendedor)),
                      ),
                      const SizedBox(height: MdSpace.md),
                      MdActionTile(
                        icone: Icons.local_shipping_outlined,
                        titulo: 'Entregas do dia',
                        subtitulo: subtituloEntregas(_prontos),
                        onTap: () => _abrir(EntregasPage(vendedor: widget.vendedor)),
                      ),
                      const SizedBox(height: MdSpace.md),
                      MdActionTile(
                        icone: Icons.receipt_long_outlined,
                        titulo: 'Meus pedidos',
                        subtitulo: 'Ver, editar e compartilhar',
                        onTap: () => _abrir(PedidosPage(vendedorCodigo: _codigo, vendedor: widget.vendedor)),
                      ),
                      const SizedBox(height: MdSpace.md),
                      MdActionTile(
                        icone: Icons.person_search_outlined,
                        titulo: 'Clientes sumidos',
                        subtitulo: subtituloSumidos(_sumidos),
                        onTap: () => _abrir(ClientesSumidosPage(vendedor: widget.vendedor)),
                      ),
                      const SizedBox(height: MdSpace.md),
                      MdActionTile(
                        icone: Icons.bar_chart_outlined,
                        titulo: 'Minhas vendas',
                        subtitulo: _subtituloVendas(),
                        onTap: () => _abrir(MinhasVendasPage(vendedor: widget.vendedor)),
                      ),
                      if (leituraDeEtiquetaDisponivel) ...[
                        const SizedBox(height: MdSpace.md),
                        MdActionTile(
                          icone: Icons.qr_code_scanner,
                          titulo: 'Ler etiqueta',
                          subtitulo: 'Registrar a entrega pelo QR',
                          onTap: () => _abrir(LerEtiquetaPage(vendedorCodigo: _codigo)),
                        ),
                      ],
                      if (_sincronizando) ...[
                        const SizedBox(height: MdSpace.xl),
                        _linhaSincronizando(tt),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      MdSpace.lg, MdSpace.xl, MdSpace.lg, MdSpace.lg),
                  child: Text(
                    'Versão 1.0 • MilkDim Alimentos',
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
