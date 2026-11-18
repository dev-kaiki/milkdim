// lib/pages/home_page.dart
//
// • Ao abrir: se a última sync completa tem 7 dias ou mais, sincroniza (com
//   internet) ou só avisa (sem internet) — nunca impede o vendedor de trabalhar.
//   Com internet e sync em dia, tenta subir os pedidos aguardando envio.
// • Mostra "N pedidos aguardando envio" com o botão "Enviar agora".
// • "Sair" fica bloqueado enquanto houver pedido aguardando envio. A volta para
//   o login é feita pelo listener de sessão do main.dart.
// • "Visualizar Pedidos" passa o vendedorCodigo para filtrar.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/auth.dart';
import '../utils/colors.dart';
import '../utils/db.dart';
import '../utils/supabase_helper.dart';
import 'pedido_page.dart';
import 'pedidos_page.dart';
import 'configuracoes_page.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  const HomePage({super.key, required this.vendedor});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _pendentes = 0;
  bool _sincronizando = false;
  bool _enviando = false;

  String get _codigo => widget.vendedor['codigo']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _aoAbrir();
  }

  Future<void> _aoAbrir() async {
    await _atualizarPendentes();
    if (_codigo.isEmpty) return;
    final online = await temInternet();
    final vencida = await syncVencida();
    if (!mounted) return;
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

  Future<void> _atualizarPendentes() async {
    if (_codigo.isEmpty) return;
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
    setState(() => _sincronizando = false);
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
        backgroundColor: milkdimWhite,
        title: const Text('Sincronização atrasada', style: TextStyle(color: milkdimOrange)),
        content: const Text(
          'Faz 7 dias ou mais sem sincronizar.\n\n'
          'Você pode continuar trabalhando, mas conecte à internet assim que puder '
          'para atualizar clientes, produtos e pedidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: milkdimDarkOrange)),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarPendentes({bool silencioso = false}) async {
    if (_enviando || _codigo.isEmpty) return;
    setState(() => _enviando = true);
    ({int enviados, int falhas})? r;
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
        backgroundColor: milkdimWhite,
        title: const Text('Sair', style: TextStyle(color: milkdimOrange)),
        content: const Text('Para entrar de novo será preciso internet. Deseja sair?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: milkdimDarkOrange)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: milkdimOrange,
              foregroundColor: milkdimWhite,
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: sucesso ? milkdimOrange : milkdimDarkOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: sucesso ? 2 : 4),
      ),
    );
  }

  Widget _avisoPendentes() {
    final texto = _pendentes == 1
        ? '1 pedido aguardando envio'
        : '$_pendentes pedidos aguardando envio';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: milkdimYellow.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: milkdimOrange, width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload, color: milkdimDarkOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: milkdimDarkOrange,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          _enviando
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: milkdimOrange, strokeWidth: 3),
                )
              : OutlinedButton(
                  onPressed: _sincronizando ? null : () => _enviarPendentes(),
                  child: const Text('Enviar agora'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        backgroundColor: milkdimWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: milkdimOrange),
        title: Row(
          children: [
            Image.asset('assets/logo.jpg', height: 36),
            const SizedBox(width: 12),
            const Text(
              'MilkDim',
              style: TextStyle(
                color: milkdimOrange,
                fontWeight: FontWeight.bold,
                fontSize: 25,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: milkdimDarkOrange),
            onPressed: () => _abrir(const ConfiguracoesPage()),
            tooltip: 'Configurações',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: milkdimDarkOrange),
            onPressed: _sair,
            tooltip: 'Sair',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_sincronizando) ...[
                const LinearProgressIndicator(color: milkdimOrange),
                const SizedBox(height: 8),
                const Text(
                  'Sincronizando dados…',
                  style: TextStyle(color: milkdimDarkOrange),
                ),
                const SizedBox(height: 18),
              ],
              if (_pendentes > 0) ...[
                _avisoPendentes(),
                const SizedBox(height: 26),
              ],
              ElevatedButton.icon(
                onPressed: () => _abrir(PedidoPage(vendedor: widget.vendedor)),
                icon: const Icon(Icons.add_shopping_cart, color: milkdimWhite, size: 30),
                label: const Text(
                  'Novo Pedido',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: milkdimOrange,
                  foregroundColor: milkdimWhite,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(fontSize: 21),
                ),
              ),
              const SizedBox(height: 26),
              ElevatedButton.icon(
                onPressed: () => _abrir(PedidosPage(vendedorCodigo: _codigo)),
                icon: const Icon(Icons.list_alt, color: milkdimDarkOrange, size: 30),
                label: const Text(
                  'Visualizar Pedidos',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: milkdimYellow.withValues(alpha: 0.45),
                  foregroundColor: milkdimDarkOrange,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(fontSize: 21),
                ),
              ),
              const SizedBox(height: 34),
              const Text(
                'Versão 1.0 • MilkDim Alimentos',
                style: TextStyle(fontSize: 14, color: milkdimDarkOrange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
