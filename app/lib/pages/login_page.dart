// lib/pages/login_page.dart
//
// Ajustes:
// • mounted checks após awaits para evitar use_build_context_synchronously
// • troca de withOpacity() -> withValues(alpha: …)
// • mensagens mais consistentes
// • pequenos refinamentos de fluxo de login/sincronização

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/colors.dart';
import '../utils/supabase_helper.dart';
import '../utils/db.dart';
import '../utils/auth.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _codigoCtrl = TextEditingController();
  final TextEditingController _senhaCtrl = TextEditingController();
  bool carregando = false;

  static const String _keyUltimaSync = 'ultima_sincronizacao';

  Future<bool> _syncEmDia() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMillis = prefs.getInt(_keyUltimaSync);
    if (lastSyncMillis == null) return false;
    final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncMillis);
    return DateTime.now().difference(lastSync) < const Duration(days: 7);
  }

  Future<void> _atualizarUltimaSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUltimaSync, DateTime.now().millisecondsSinceEpoch);
  }

  bool _isAtivo(dynamic valor) {
    if (valor == null) return false;
    if (valor is bool) return valor;
    if (valor is int) return valor == 1;
    if (valor is String) return valor == 'true' || valor == '1';
    return false;
  }

  Future<void> _login() async {
    final codigo = _codigoCtrl.text.trim();
    final senha = _senhaCtrl.text;
    if (codigo.isEmpty || senha.isEmpty) {
      _showMsg('Preencha todos os campos!');
      return;
    }

    final emDia = await _syncEmDia();
    if (!emDia) {
      await _showSyncDialogObrigatorio();
      return;
    }

    setState(() => carregando = true);

    // LOGIN LOCAL
    final vendedorLocal = await loginLocalVendedor(codigo, senha);
    if (!mounted) return;
    if (vendedorLocal != null) {
      if (!_isAtivo(vendedorLocal['ativo'])) {
        _showMsg('Vendedor inativo! Consulte o administrador.');
      } else {
        _showMsg('Login realizado com sucesso!', isError: false);
        setState(() => carregando = false);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(vendedor: vendedorLocal)),
        );
        return;
      }
      setState(() => carregando = false);
      return;
    }

    // LOGIN SUPABASE AUTH
    Map<String, dynamic>? vendedorSupabase;
    try {
      vendedorSupabase = await entrar(codigo, senha);
    } on LoginRecusado catch (e) {
      if (!mounted) return;
      _showMsg(e.mensagem);
      setState(() => carregando = false);
      return;
    } catch (_) {
      vendedorSupabase = null;
    }
    if (!mounted) return;
    if (vendedorSupabase != null) {
      if (!_isAtivo(vendedorSupabase['ativo'])) {
        _showMsg('Vendedor inativo! Consulte o administrador.');
      } else {
        _showMsg('Login online OK!', isError: false);
        setState(() => carregando = false);
        final vendedor = vendedorSupabase;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomePage(vendedor: vendedor)),
        );
        return;
      }
      setState(() => carregando = false);
      return;
    }

    _showMsg('Login ou senha inválidos!');
    setState(() => carregando = false);
  }

  Future<void> _sincronizar() async {
    final vendedor = await vendedorLocal();
    final codigo = vendedor?['codigo']?.toString() ?? '';
    if (codigo.isEmpty) {
      _showMsg('Entre com internet para sincronizar.');
      return;
    }
    if (!mounted) return;
    setState(() => carregando = true);
    final sucesso = await sincronizarTudo(vendedorCodigo: codigo);
    if (!mounted) return;
    if (sucesso) {
      await _atualizarUltimaSync();
      if (!mounted) return;
      _showMsg('Sincronização realizada!', isError: false);
    } else {
      _showMsg('Erro ao sincronizar dados.');
    }
    setState(() => carregando = false);
  }

  Future<void> _showSyncDialogObrigatorio() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Sincronização obrigatória'),
        content: const Text(
          'Você precisa sincronizar os dados antes de entrar no sistema.\n\n'
              'A sincronização deve ser feita a cada 7 dias para garantir funcionamento offline e atualização dos dados.',
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: milkdimOrange,
              foregroundColor: milkdimWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar agora'),
            onPressed: () async {
              Navigator.of(context).pop();
              await _sincronizar();
            },
          ),
        ],
      ),
    );
  }

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? milkdimDarkOrange : milkdimOrange,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.jpg', height: 100),
              const SizedBox(height: 30),
              const Text(
                'MilkDim Alimentos',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: milkdimOrange,
                  fontSize: 24,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codigoCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Código do vendedor',
                  prefixIcon: const Icon(Icons.badge, color: milkdimDarkOrange),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                  fillColor: milkdimYellow.withValues(alpha: 0.10),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _senhaCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: const Icon(Icons.lock, color: milkdimDarkOrange),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                  fillColor: milkdimYellow.withValues(alpha: 0.10),
                ),
              ),
              const SizedBox(height: 18),
              carregando
                  ? const CircularProgressIndicator(color: milkdimOrange)
                  : SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: milkdimOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  icon: const Icon(Icons.login, color: milkdimYellow),
                  label: const Text(
                    'Entrar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: milkdimYellow,
                      fontSize: 20,
                    ),
                  ),
                  onPressed: _login,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: carregando ? null : _sincronizar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: milkdimDarkOrange,
                  minimumSize: const Size(180, 46),
                  side: const BorderSide(color: milkdimOrange, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar Dados'),
              ),
              const SizedBox(height: 38),
              Text(
                '© ${DateTime.now().year} MilkDim Alimentos\nTodos os direitos reservados.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: milkdimDarkOrange.withValues(alpha: 0.67),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
