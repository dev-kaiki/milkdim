// lib/pages/login_page.dart
//
// Login pelo Supabase Auth (`entrar`). Precisa de internet só no primeiro
// acesso do aparelho ou depois de "Sair"; com sessão salva o app abre na Home.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/colors.dart';
import '../utils/auth.dart';
import '../utils/supabase_helper.dart' show temInternet;
import 'home_page.dart';

const String _msgInativo = 'Vendedor inativo. Fale com o administrador.';

/// Texto mostrado quando [entrar] falha. [online] diz se há internet agora.
String mensagemErroLogin(Object erro, {required bool online}) {
  if (erro is LoginRecusado) return erro.mensagem;
  if (!online) return 'O primeiro acesso precisa de internet.';
  if (erro is AuthException) {
    // Banido também chega como 400: testar antes do 400 genérico.
    if (erro.code == 'user_banned' || erro.message.toLowerCase().contains('banned')) {
      return _msgInativo;
    }
    if (erro.statusCode == '400') return 'Código ou senha inválidos.';
  }
  return 'Não foi possível entrar. Tente de novo.';
}

int _loginsMontados = 0;

/// `true` enquanto a tela de login está montada (evita navegar para ela de novo
/// quando o `signOut` acontece a partir dela).
bool get telaDeLoginAberta => _loginsMontados > 0;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _codigoCtrl = TextEditingController();
  final TextEditingController _senhaCtrl = TextEditingController();
  bool carregando = false;

  @override
  void initState() {
    super.initState();
    _loginsMontados++;
  }

  bool _isAtivo(dynamic valor) {
    if (valor == null) return false;
    if (valor is bool) return valor;
    if (valor is int) return valor == 1;
    if (valor is String) return valor == 'true' || valor == '1';
    return false;
  }

  /// Login sempre pelo Supabase Auth. A sync de 7 dias roda depois, na Home,
  /// e nunca impede a entrada.
  Future<void> _login() async {
    if (carregando) return;
    final codigo = _codigoCtrl.text.trim();
    final senha = _senhaCtrl.text;
    if (codigo.isEmpty || senha.isEmpty) {
      _showMsg('Preencha todos os campos!');
      return;
    }

    setState(() => carregando = true);

    final Map<String, dynamic> vendedor;
    try {
      vendedor = await entrar(codigo, senha);
    } catch (e) {
      final online = e is LoginRecusado || await temInternet();
      if (!mounted) return;
      _showMsg(mensagemErroLogin(e, online: online));
      setState(() => carregando = false);
      return;
    }

    if (!_isAtivo(vendedor['ativo'])) {
      // Login acabou de dar certo: não há pendentes a proteger aqui.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      _showMsg(_msgInativo);
      setState(() => carregando = false);
      return;
    }

    if (!mounted) return;
    setState(() => carregando = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(vendedor: vendedor)),
    );
  }

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? milkdimDarkOrange : milkdimOrange,
        duration: Duration(seconds: isError ? 4 : 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  void dispose() {
    _loginsMontados--;
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
