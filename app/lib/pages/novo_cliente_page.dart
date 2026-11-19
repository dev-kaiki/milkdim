// lib/pages/novo_cliente_page.dart
//
// Cria cliente localmente no SQLite usando apenas colunas do schema.
// (Opcional) descomente a chamada para enviar ao Supabase.
// Visual do milkdim_ui (tema + componentes) e pequenos validates.

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/db.dart';
// import '../utils/supabase_helper.dart'; // <- descomente se for usar inserirClienteSupabase()

class NovoClientePage extends StatefulWidget {
  const NovoClientePage({super.key});

  @override
  State<NovoClientePage> createState() => _NovoClientePageState();
}

class _NovoClientePageState extends State<NovoClientePage> {
  final _formKey = GlobalKey<FormState>();

  final _nome = TextEditingController();
  final _nomeFantasia = TextEditingController();
  final _cpfCnpj = TextEditingController();
  final _telefone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _endereco = TextEditingController();
  final _cidade = TextEditingController();
  final _cep = TextEditingController();
  final _inscEstadual = TextEditingController();
  final _anotacao = TextEditingController();

  bool _salvando = false;

  @override
  void dispose() {
    _nome.dispose();
    _nomeFantasia.dispose();
    _cpfCnpj.dispose();
    _telefone.dispose();
    _whatsapp.dispose();
    _email.dispose();
    _endereco.dispose();
    _cidade.dispose();
    _cep.dispose();
    _inscEstadual.dispose();
    _anotacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final db = await getDb();
      final dados = <String, dynamic>{
        // id é PK simples (sem autoincrement). Usamos timestamp local para evitar colisão.
        'id': DateTime.now().millisecondsSinceEpoch,
        'nome': _nome.text.trim(),
        'nome_fantasia': _nomeFantasia.text.trim(),
        'cpf_cnpj': _cpfCnpj.text.trim(),
        'telefone': _telefone.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'email': _email.text.trim(),
        'endereco': _endereco.text.trim(),
        'cidade': _cidade.text.trim(),
        'anotacao': _anotacao.text.trim(),
        'ativo': 1,
        'datahora': DateTime.now().toUtc().toIso8601String(),
        'insc_estadual': _inscEstadual.text.trim(),
        'cep': _cep.text.trim(),
      };

      await db.insert('clientes', dados, conflictAlgorithm: ConflictAlgorithm.replace);

      // (opcional) envie ao Supabase:
      // await inserirClienteSupabase(dados);

      if (!mounted) return;
      _msg('Cliente salvo!', ok: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _msg('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _msg(String m, {bool ok = false}) {
    showMdSnack(context, m, tipo: ok ? MdTipo.sucesso : MdTipo.erro);
  }

  InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
      );

  /// Dois campos lado a lado em tela larga; um embaixo do outro no celular.
  Widget _par(Widget a, Widget b, {double? larguraB}) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 480) {
          return Column(children: [a, const SizedBox(height: MdSpace.md), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: MdSpace.md),
            larguraB == null ? Expanded(child: b) : SizedBox(width: larguraB, child: b),
          ],
        );
      },
    );
  }

  Widget _secao(String titulo, List<Widget> campos) {
    final filhos = <Widget>[];
    for (final c in campos) {
      if (filhos.isNotEmpty) filhos.add(const SizedBox(height: MdSpace.md));
      filhos.add(c);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: MdSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MdSectionHeader(titulo: titulo),
          MdCard(child: Column(children: filhos)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Cliente')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MdSpace.lg),
            child: MdContentWidth(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _secao('Identificação', [
                    TextFormField(
                      controller: _nome,
                      decoration: _dec('Nome', icon: Icons.person_outline),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                    ),
                    TextFormField(
                      controller: _nomeFantasia,
                      decoration: _dec('Nome Fantasia', icon: Icons.storefront_outlined),
                    ),
                    _par(
                      TextFormField(
                        controller: _cpfCnpj,
                        keyboardType: TextInputType.number,
                        decoration: _dec('CPF/CNPJ', icon: Icons.badge_outlined),
                      ),
                      TextFormField(
                        controller: _inscEstadual,
                        decoration: _dec('Insc. Estadual', icon: Icons.confirmation_number_outlined),
                      ),
                    ),
                  ]),
                  _secao('Contato', [
                    _par(
                      TextFormField(
                        controller: _telefone,
                        keyboardType: TextInputType.phone,
                        decoration: _dec('Telefone', icon: Icons.phone_outlined),
                      ),
                      TextFormField(
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        decoration: _dec('WhatsApp', icon: Icons.sms_outlined),
                      ),
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _dec('E-mail', icon: Icons.email_outlined),
                    ),
                  ]),
                  _secao('Endereço', [
                    TextFormField(
                      controller: _endereco,
                      decoration: _dec('Endereço', icon: Icons.home_outlined),
                    ),
                    _par(
                      TextFormField(
                        controller: _cidade,
                        decoration: _dec('Cidade', icon: Icons.location_city_outlined),
                      ),
                      TextFormField(
                        controller: _cep,
                        keyboardType: TextInputType.number,
                        decoration: _dec('CEP', icon: Icons.map_outlined),
                      ),
                      larguraB: 180,
                    ),
                  ]),
                  _secao('Observações', [
                    TextFormField(
                      controller: _anotacao,
                      maxLines: 2,
                      decoration: _dec('Anotação', icon: Icons.notes),
                    ),
                  ]),
                  const SizedBox(height: MdSpace.sm),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: MdColors.textMuted,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Salvar'),
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
