import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_admin.dart';

const Color milkdimYellow = Color(0xFFFFE066);
const Color milkdimOrange = Color(0xFFE38A1D);
const Color milkdimWhite  = Color(0xFFFFFFFF);
const Color milkdimDarkOrange = Color(0xFFC06617);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usuarioCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _senhaFocus = FocusNode();

  bool _loading = false;
  bool _showSenha = false;
  String? _errorMsg;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    // Se já houver sessão salva, pula pro /home.
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfAlreadyLogged());
  }

  Future<void> _redirectIfAlreadyLogged() async {
    if (Supabase.instance.client.auth.currentSession != null && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _usuarioCtrl.dispose();
    _senhaCtrl.dispose();
    _senhaFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      await entrarAdmin(_usuarioCtrl.text, _senhaCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } catch (e) {
      if (mounted) setState(() => _errorMsg = mensagemErroLoginAdmin(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: milkdimYellow,
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // LOGO
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: milkdimWhite,
                      boxShadow: [
                        BoxShadow(
                          color: milkdimOrange.withOpacity(0.18),
                          blurRadius: 32,
                          spreadRadius: 4,
                          offset: const Offset(0, 6),
                        )
                      ],
                      border: Border.all(color: milkdimOrange.withOpacity(0.14), width: 3.5),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/logo_circular.png',
                        width: 86,
                        height: 86,
                        errorBuilder: (_, __, ___) =>
                        const Icon(Icons.local_cafe, size: 64, color: milkdimOrange),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'MilkDim Admin',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                      color: milkdimDarkOrange,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          color: milkdimOrange.withOpacity(0.09),
                          blurRadius: 5,
                          offset: const Offset(1, 2),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Acesso exclusivo',
                    style: TextStyle(color: milkdimOrange.withOpacity(0.80), fontSize: 14.5, letterSpacing: 1),
                  ),
                  const SizedBox(height: 32),

                  // CARD
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    elevation: 7,
                    color: milkdimWhite,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // USUÁRIO
                            TextFormField(
                              controller: _usuarioCtrl,
                              autofillHints: const [AutofillHints.username],
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _senhaFocus.requestFocus(),
                              onChanged: (_) {
                                if (_errorMsg != null) setState(() => _errorMsg = null);
                              },
                              style: const TextStyle(
                                fontSize: 18,
                                color: milkdimDarkOrange,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                labelText: "Usuário",
                                labelStyle: const TextStyle(
                                  color: milkdimDarkOrange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 1.1,
                                ),
                                prefixIcon: const Icon(Icons.person_outline, color: milkdimOrange, size: 26),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: milkdimOrange),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: milkdimDarkOrange, width: 2),
                                ),
                                filled: true,
                                fillColor: milkdimYellow.withOpacity(0.08),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o usuário' : null,
                            ),
                            const SizedBox(height: 16),

                            // SENHA
                            TextFormField(
                              controller: _senhaCtrl,
                              focusNode: _senhaFocus,
                              autofillHints: const [AutofillHints.password],
                              obscureText: !_showSenha,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _loading ? null : _login(),
                              onChanged: (_) {
                                if (_errorMsg != null) setState(() => _errorMsg = null);
                              },
                              style: const TextStyle(
                                fontSize: 18,
                                letterSpacing: 2,
                                color: milkdimDarkOrange,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                labelText: "Senha",
                                labelStyle: const TextStyle(
                                  color: milkdimDarkOrange,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 1.1,
                                ),
                                prefixIcon: const Icon(Icons.lock_outline, color: milkdimOrange, size: 26),
                                suffixIcon: IconButton(
                                  tooltip: _showSenha ? 'Ocultar' : 'Mostrar',
                                  onPressed: () => setState(() => _showSenha = !_showSenha),
                                  icon: Icon(_showSenha ? Icons.visibility_off : Icons.visibility,
                                      color: milkdimOrange),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: milkdimOrange),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: milkdimDarkOrange, width: 2),
                                ),
                                filled: true,
                                fillColor: milkdimYellow.withOpacity(0.08),
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha' : null,
                            ),
                            const SizedBox(height: 16),

                            // ERRO
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _errorMsg == null ? 0.0 : 1.0,
                              child: _errorMsg == null
                                  ? const SizedBox.shrink()
                                  : Row(
                                children: [
                                  const Icon(Icons.error, color: Colors.red, size: 18),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _errorMsg!,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // BOTÃO
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: milkdimOrange,
                                  foregroundColor: milkdimWhite,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 2,
                                ),
                                onPressed: _loading
                                    ? null
                                    : () {
                                  if (_formKey.currentState!.validate()) {
                                    _login();
                                  }
                                },
                                child: _loading
                                    ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(color: milkdimWhite, strokeWidth: 3.1),
                                )
                                    : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.login, color: milkdimWhite),
                                    SizedBox(width: 12),
                                    Text(
                                      'Entrar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 19,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text(
                    '© ${DateTime.now().year} MilkDim Alimentos',
                    style: TextStyle(
                      color: milkdimDarkOrange.withOpacity(0.48),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
