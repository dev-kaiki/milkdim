import 'package:flutter/material.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_admin.dart';

// Tabs sem conflito
import '../tabs/vendedores_tab.dart';
import '../tabs/clientes_tab.dart';

// Use aliases para separar os nomes
import '../tabs/produtos_tab.dart' as prod;
import '../tabs/pedidos_tab.dart' as ped;

const Color milkdimYellow = Color(0xFFFFE066);
const Color milkdimOrange = Color(0xFFE38A1D);
const Color milkdimWhite  = Color(0xFFFFFFFF);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _loggingOut = false;
  DateTime? _lastBackPress;
  StreamSubscription<AuthState>? _authSub;

  final List<Widget> _tabs = [
    const VendedoresTab(),
    const prod.ProdutosTab(),
    const ped.PedidosTab(),
    const ClientesTab(),
  ];

  static const List<String> _titles = [
    'Vendedores',
    'Produtos',
    'Pedidos',
    'Clientes',
  ];

  static const List<IconData> _tabIcons = [
    Icons.people_alt_rounded,
    Icons.shopping_bag_rounded,
    Icons.receipt_long_rounded,
    Icons.groups_rounded,
  ];

  @override
  void initState() {
    super.initState();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem acesso ao controle.')),
      );
      _goLogin();
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: milkdimWhite,
        title: Row(
          children: [
            const Icon(Icons.logout, color: milkdimOrange),
            const SizedBox(width: 8),
            const Text('Sair da conta',
                style: TextStyle(color: milkdimOrange, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Tem certeza que deseja sair?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: milkdimOrange, foregroundColor: milkdimWhite),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível sair. Tente novamente.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Toque novamente para sair'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: milkdimWhite,
        appBar: AppBar(
          backgroundColor: milkdimYellow,
          elevation: 0,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo.jpg',
                height: 34,
                errorBuilder: (_, __, ___) =>
                const Icon(Icons.local_cafe, size: 32, color: milkdimOrange),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _titles[_selectedIndex],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: milkdimOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (_loggingOut)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: milkdimOrange, strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.logout, color: milkdimOrange),
                tooltip: 'Sair',
                onPressed: _signOut,
              ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(index: _selectedIndex, children: _tabs),
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: milkdimYellow,
          selectedItemColor: milkdimOrange,
          unselectedItemColor: milkdimOrange.withOpacity(0.55),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: List.generate(
            _tabs.length,
                (i) => BottomNavigationBarItem(icon: Icon(_tabIcons[i]), label: _titles[i]),
          ),
        ),
      ),
    );
  }
}
