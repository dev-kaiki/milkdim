// lib/main.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// SQLite (mobile & desktop)
import 'package:sqflite/sqflite.dart'; // expõe 'databaseFactory'
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // sqfliteFfiInit + databaseFactoryFfi

import 'utils/auth.dart';
import 'utils/http_prazo.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ativa SQLite FFI em desktop (Windows/Linux/macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  try {
    // Credenciais entram no build, nunca no codigo:
    //   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError('SUPABASE_URL e SUPABASE_ANON_KEY nao configurados.');
    }
    // Prazo nas requisições: nada fica preso esperando a rede para sempre.
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      httpClient: ClienteHttpComPrazo(),
    );
    debugPrint('🟢 Supabase inicializado com sucesso');

    runApp(const MilkDimApp());
  } catch (e) {
    debugPrint('❌ Erro ao inicializar Supabase: $e');
    runApp(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(MdSpace.xl),
          child: Center(
            child: MdBanner(
              tipo: MdTipo.erro,
              texto: 'Erro ao inicializar Supabase!\nVerifique conexão e credenciais.',
            ),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    ));
  }
}

class MilkDimApp extends StatefulWidget {
  const MilkDimApp({super.key});

  @override
  State<MilkDimApp> createState() => _MilkDimAppState();
}

class _MilkDimAppState extends State<MilkDimApp> {
  // A sync só roda com sessão (depois do login), nunca anônima aqui.
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;

  // Decidida uma vez, na abertura. Sessão salva (mesmo vencida e offline)
  // abre direto na Home.
  late final RotaInicial _rota = rotaInicial(
      temSessao: Supabase.instance.client.auth.currentSession != null);

  @override
  void initState() {
    super.initState();
    // Sessão encerrada (Sair, senha trocada, vendedor desativado/excluído):
    // volta para o login. Nunca mexe no SQLite. Se o signOut veio da própria
    // tela de login (login recusado), já estamos lá.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (estado) {
        if (estado.event != AuthChangeEvent.signedOut || telaDeLoginAberta) return;
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      },
      onError: (Object e) => debugPrint('Auth: $e'),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'MilkDim Alimentos',
      theme: buildMilkdimTheme(),
      debugShowCheckedModeBanner: false,
      home: _rota == RotaInicial.home ? const _AberturaComSessao() : const LoginPage(),
    );
  }
}

/// Com sessão salva: carrega o vendedor do aparelho e abre a Home.
class _AberturaComSessao extends StatefulWidget {
  const _AberturaComSessao();

  @override
  State<_AberturaComSessao> createState() => _AberturaComSessaoState();
}

class _AberturaComSessaoState extends State<_AberturaComSessao> {
  Map<String, dynamic>? _vendedor;
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    Map<String, dynamic>? v;
    try {
      v = await vendedorLocal();
    } catch (e) {
      debugPrint('Erro ao ler vendedor local: $e');
    }
    if (!mounted) return;
    setState(() {
      _vendedor = v;
      _carregado = true;
    });
    if (v == null) {
      // Sessão sem vendedor local: encerra depois que o login estiver na tela.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final v = _vendedor;
    return v == null ? const LoginPage() : HomePage(vendedor: v);
  }
}
