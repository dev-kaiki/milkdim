// lib/main.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// SQLite (mobile & desktop)
import 'package:sqflite/sqflite.dart'; // expõe 'databaseFactory'
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // sqfliteFfiInit + databaseFactoryFfi

import 'utils/colors.dart';
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
    await Supabase.initialize(url: url, anonKey: anonKey);
    debugPrint('🟢 Supabase inicializado com sucesso');

    runApp(const MilkDimApp());
  } catch (e) {
    debugPrint('❌ Erro ao inicializar Supabase: $e');
    runApp(const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'Erro ao inicializar Supabase!\nVerifique conexão e credenciais.',
            style: TextStyle(
              color: Colors.red,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
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
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MilkDim Alimentos',
      theme: ThemeData(
        primaryColor: milkdimOrange,
        scaffoldBackgroundColor: milkdimWhite,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: milkdimOrange,
          secondary: milkdimDarkOrange,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: milkdimWhite,
          elevation: 1,
          iconTheme: IconThemeData(color: milkdimOrange),
          titleTextStyle: TextStyle(
            color: milkdimOrange,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: milkdimOrange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: milkdimDarkOrange,
            side: const BorderSide(color: milkdimOrange, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: milkdimYellow.withOpacity(0.10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          labelStyle: const TextStyle(color: milkdimDarkOrange),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}

/// 🔌 Verifica conexão com a internet
Future<bool> temInternet() async {
  try {
    final result = await InternetAddress.lookup('example.com');
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
