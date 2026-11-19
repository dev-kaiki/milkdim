import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_admin.dart';

class LoginPage extends StatefulWidget {
  /// Se há sessão salva, pula para /home. Falso só na captura visual (sem Supabase).
  final bool verificarSessaoSalva;

  const LoginPage({super.key, this.verificarSessaoSalva = true});
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
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    // Se já houver sessão salva, pula pro /home.
    if (widget.verificarSessaoSalva) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfAlreadyLogged());
    }
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
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: MdSpace.xl, vertical: MdSpace.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // LOGO
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: const Image(
                          image: MdLogoTitle.logoPadrao,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          semanticLabel: 'Logo MilkDim',
                        ),
                      ),
                      const SizedBox(height: MdSpace.lg),
                      Text('MilkDim Admin', style: tt.headlineSmall),
                      const SizedBox(height: MdSpace.xs),
                      Text(
                        'Acesso exclusivo',
                        style: tt.bodyLarge!.copyWith(color: MdColors.textMuted),
                      ),
                      const SizedBox(height: MdSpace.xxl),

                      // CARD
                      MdCard(
                        padding: const EdgeInsets.all(MdSpace.xl),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                style: tt.bodyLarge,
                                decoration: const InputDecoration(
                                  labelText: "Usuário",
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Informe o usuário' : null,
                              ),
                              const SizedBox(height: MdSpace.lg),

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
                                style: tt.bodyLarge,
                                decoration: InputDecoration(
                                  labelText: "Senha",
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _showSenha ? 'Ocultar' : 'Mostrar',
                                    onPressed: () => setState(() => _showSenha = !_showSenha),
                                    icon: Icon(_showSenha ? Icons.visibility_off : Icons.visibility),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha' : null,
                              ),

                              // ERRO
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                child: _errorMsg == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        padding: const EdgeInsets.only(top: MdSpace.lg),
                                        child: MdBanner(tipo: MdTipo.erro, texto: _errorMsg!),
                                      ),
                              ),
                              const SizedBox(height: MdSpace.xl),

                              // BOTÃO
                              SizedBox(
                                height: 52,
                                child: FilledButton(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          if (_formKey.currentState!.validate()) {
                                            _login();
                                          }
                                        },
                                  child: _loading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: MdColors.primaryFill,
                                            strokeWidth: 3,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.login),
                                            SizedBox(width: MdSpace.md),
                                            Text('Entrar'),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: MdSpace.xxl),
                      Text(
                        '© ${DateTime.now().year} MilkDim Alimentos',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
