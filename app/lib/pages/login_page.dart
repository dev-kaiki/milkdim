// lib/pages/login_page.dart
//
// Login pelo Supabase Auth (`entrar`). Precisa de internet só no primeiro
// acesso do aparelho ou depois de "Sair"; com sessão salva o app abre na Home.

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    showMdSnack(context, msg, tipo: isError ? MdTipo.erro : MdTipo.sucesso);
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: MdSpace.xl, vertical: MdSpace.xxl),
            child: MdContentWidth(
              maxWidth: 420,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(MdRadius.dialog),
                      child: const Image(
                        image: MdLogoTitle.logoPadrao,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        semanticLabel: 'Logo MilkDim',
                      ),
                    ),
                  ),
                  const SizedBox(height: MdSpace.lg),
                  Text(
                    'MilkDim Alimentos',
                    style: tt.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MdSpace.xs),
                  Text(
                    'Entre com seu código de vendedor',
                    style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MdSpace.xl),
                  MdCard(
                    padding: const EdgeInsets.all(MdSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _codigoCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Código do vendedor',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: MdSpace.md),
                        TextField(
                          controller: _senhaCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: MdSpace.xl),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: carregando ? null : _login,
                            icon: carregando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: MdColors.textMuted,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: const Text('Entrar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MdSpace.xxl),
                  Text(
                    '© ${DateTime.now().year} MilkDim Alimentos\nTodos os direitos reservados.',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
