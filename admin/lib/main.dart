import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';

/// Use --dart-define em build/run. Ex.:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

// Lê das env vars (compile-time). Se vier vazio, usa o fallback abaixo.
const String _ENV_SB_URL  = String.fromEnvironment('SUPABASE_URL');
const String _ENV_SB_ANON = String.fromEnvironment('SUPABASE_ANON_KEY');

// Sem fallback: uma credencial embutida aqui iria junto em todo build.
// Passe no build: --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const String _FALLBACK_SB_URL  = '';
const String _FALLBACK_SB_ANON = '';

// Valores finais usados pela app.
const String _SB_URL  = _ENV_SB_URL  != '' ? _ENV_SB_URL  : _FALLBACK_SB_URL;
const String _SB_ANON = _ENV_SB_ANON != '' ? _ENV_SB_ANON : _FALLBACK_SB_ANON;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Em debug, avisa se estiver usando fallback.
  assert(() {
    if (_ENV_SB_URL == '' || _ENV_SB_ANON == '') {
      // ignore: avoid_print
      print('[MilkDim Admin] Usando fallbacks do Supabase (defina via --dart-define em produção).');
    }
    return true;
  }());

  // Garante que temos valores.
  assert(
  _SB_URL.isNotEmpty && _SB_ANON.isNotEmpty,
  'Defina SUPABASE_URL e SUPABASE_ANON_KEY via --dart-define ou ajuste os fallbacks no main.dart.',
  );

  await Supabase.initialize(
    url: _SB_URL,
    anonKey: _SB_ANON,
    debug: kDebugMode,
  );

  runApp(const MilkDimAdminApp());
}

class MilkDimAdminApp extends StatelessWidget {
  const MilkDimAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MilkDim Admin',
      theme: buildMilkdimTheme(),
      debugShowCheckedModeBanner: false,

      // Só pela existência da sessão salva (nunca por isExpired).
      initialRoute: Supabase.instance.client.auth.currentSession != null ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginPage(),
        '/home' : (_) => const HomePage(),
      },
      onUnknownRoute: (_) => MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }
}

