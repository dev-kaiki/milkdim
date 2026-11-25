import 'package:flutter/material.dart';
import 'dart:async';

import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_admin.dart';

// Tabs sem conflito
import '../tabs/vendedores_tab.dart';
import '../tabs/clientes_tab.dart';
import '../tabs/producao_tab.dart';
import '../tabs/financeiro_tab.dart';

// Use aliases para separar os nomes
import '../tabs/produtos_tab.dart' as prod;
import '../tabs/pedidos_tab.dart' as ped;

/// Largura a partir da qual a navegação vira trilho lateral (Windows/tablet deitado).
const double _larguraTrilho = 900;

/// Largura a partir da qual o trilho mostra os rótulos ao lado dos ícones.
const double _larguraTrilhoEstendido = 1200;

class HomePage extends StatefulWidget {
  /// Só para captura visual (sem Supabase): troca as abas e desliga as
  /// checagens de sessão. Nulo (padrão) mantém o comportamento normal.
  @visibleForTesting
  final List<Widget>? abasDeTeste;

  /// Aba aberta ao montar (padrão: Produção).
  final int indiceInicial;

  const HomePage({super.key, this.abasDeTeste, this.indiceInicial = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex = widget.indiceInicial;
  bool _loggingOut = false;
  DateTime? _lastBackPress;
  StreamSubscription<AuthState>? _authSub;

  late final List<Widget> _tabs = widget.abasDeTeste ??
      [
        const ProducaoTab(),
        const VendedoresTab(),
        const prod.ProdutosTab(),
        const ped.PedidosTab(),
        const ClientesTab(),
        const FinanceiroTab(),
      ];

  static const List<String> _titles = [
    'Produção',
    'Vendedores',
    'Produtos',
    'Pedidos',
    'Clientes',
    'Financeiro',
  ];

  static const List<IconData> _tabIcons = [
    Icons.factory_rounded,
    Icons.people_alt_rounded,
    Icons.shopping_bag_rounded,
    Icons.receipt_long_rounded,
    Icons.groups_rounded,
    Icons.account_balance_wallet_rounded,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.abasDeTeste != null) return; // captura visual: sem Supabase
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLogged());
    // Sessão encerrada (logout, token revogado, conta desativada): volta ao login.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) _goLogin();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _ensureLogged() async {
    if (Supabase.instance.client.auth.currentSession == null) {
      _goLogin();
      return;
    }
    // Sessão salva pode ser de conta não-admin (app fechado durante o login).
    if (!await sessaoAindaEhAdmin()) {
      try {
        await sairAdmin();
      } catch (_) {}
      if (!mounted) return;
      showMdSnack(context, 'Sem acesso ao controle.', tipo: MdTipo.erro);
      _goLogin();
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: MdColors.primaryStrong),
            SizedBox(width: MdSpace.sm),
            Text('Sair da conta'),
          ],
        ),
        content: const Text('Tem certeza que deseja sair?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loggingOut = true);
    try {
      await sairAdmin();
      _goLogin();
    } catch (_) {
      if (!mounted) return;
      showMdSnack(context, 'Não foi possível sair. Tente novamente.', tipo: MdTipo.erro);
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      if (mounted) {
        // SnackBar do tema (e não showMdSnack): a duração tem que casar com a janela de 2 s.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Toque novamente para sair'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
    return true;
  }

  void _selecionar(int i) => setState(() => _selectedIndex = i);

  // A chave global mantém as abas (e o que já carregaram) quando a janela
  // cruza a largura do menu lateral e a árvore de layout muda.
  final GlobalKey _chaveAbas = GlobalKey();

  Widget _conteudo() =>
      IndexedStack(key: _chaveAbas, index: _selectedIndex, children: _tabs);

  Widget _acaoSair({required bool comRotulo}) {
    if (_loggingOut) {
      return const Padding(
        padding: EdgeInsets.all(MdSpace.md),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (comRotulo) {
      return Tooltip(
        message: 'Sair',
        child: TextButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sair'),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Sair',
      onPressed: _signOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: largura >= _larguraTrilho ? _layoutLargo(largura) : _layoutEstreito(),
    );
  }

  /// Celular / janela estreita: barra de cima com logo + seção e navegação embaixo.
  Widget _layoutEstreito() {
    return Scaffold(
      appBar: AppBar(
        title: MdLogoTitle(texto: _titles[_selectedIndex]),
        actions: [
          _acaoSair(comRotulo: false),
          const SizedBox(width: MdSpace.xs),
        ],
      ),
      body: SafeArea(child: _conteudo()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selecionar,
        destinations: List.generate(
          _tabs.length,
          (i) => NavigationDestination(icon: Icon(_tabIcons[i]), label: _titles[i]),
        ),
      ),
    );
  }

  /// Tela larga (Windows): trilho à esquerda com o logo e conteúdo centralizado.
  Widget _layoutLargo(double largura) {
    final estendido = largura >= _larguraTrilhoEstendido;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: estendido,
              minExtendedWidth: 232,
              labelType:
                  estendido ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selecionar,
              leading: Padding(
                padding: const EdgeInsets.only(top: MdSpace.sm, bottom: MdSpace.xl),
                child: estendido
                    ? const SizedBox(
                        width: 232,
                        child: Padding(
                          padding: EdgeInsets.only(left: MdSpace.xl),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: MdLogoTitle(logoSize: 36),
                          ),
                        ),
                      )
                    : const _LogoCompacto(),
              ),
              destinations: List.generate(
                _tabs.length,
                (i) => NavigationRailDestination(
                  icon: Icon(_tabIcons[i]),
                  label: Text(_titles[i]),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: MdContentWidth(
                maxWidth: 1100,
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            MdSpace.lg, MdSpace.xl, MdSpace.sm, MdSpace.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _titles[_selectedIndex],
                                style: tt.headlineSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _acaoSair(comRotulo: true),
                          ],
                        ),
                      ),
                      Expanded(child: _conteudo()),
                    ],
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

/// Só o logo, para o trilho recolhido.
class _LogoCompacto extends StatelessWidget {
  const _LogoCompacto();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: const Image(
        image: MdLogoTitle.logoPadrao,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        semanticLabel: 'Logo MilkDim',
      ),
    );
  }
}
