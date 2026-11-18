// lib/pages/novo_cliente_page.dart
//
// Cria cliente localmente no SQLite usando apenas colunas do schema.
// (Opcional) descomente a chamada para enviar ao Supabase.
// UI padronizada com cores MilkDim e pequenos validates.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/colors.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: ok ? milkdimOrange : milkdimDarkOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
    labelText: label,
    prefixIcon: icon != null ? Icon(icon, color: milkdimOrange) : null,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    filled: true,
    fillColor: milkdimYellow.withValues(alpha: 0.10),
    labelStyle: const TextStyle(color: milkdimDarkOrange),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        backgroundColor: milkdimWhite,
        elevation: 1,
        iconTheme: const IconThemeData(color: milkdimOrange),
        title: const Text('Novo Cliente', style: TextStyle(color: milkdimOrange)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextFormField(
                  controller: _nome,
                  decoration: _dec('Nome', icon: Icons.person),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nomeFantasia,
                  decoration: _dec('Nome Fantasia', icon: Icons.store),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cpfCnpj,
                        keyboardType: TextInputType.number,
                        decoration: _dec('CPF/CNPJ', icon: Icons.badge),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _inscEstadual,
                        decoration: _dec('Insc. Estadual', icon: Icons.confirmation_number),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telefone,
                        keyboardType: TextInputType.phone,
                        decoration: _dec('Telefone', icon: Icons.phone),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _whatsapp,
                        keyboardType: TextInputType.phone,
                        decoration: _dec('WhatsApp', icon: Icons.sms),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('E-mail', icon: Icons.email),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _endereco,
                  decoration: _dec('Endereço', icon: Icons.home),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cidade,
                        decoration: _dec('Cidade', icon: Icons.location_city),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        controller: _cep,
                        keyboardType: TextInputType.number,
                        decoration: _dec('CEP', icon: Icons.map),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _anotacao,
                  maxLines: 2,
                  decoration: _dec('Anotação', icon: Icons.notes),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: milkdimOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(Icons.save, color: Colors.white),
                    label: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
