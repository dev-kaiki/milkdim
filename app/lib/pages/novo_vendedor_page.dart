// lib/pages/novo_vendedor_page.dart

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/colors.dart';
import '../utils/db.dart';
import '../utils/supabase_helper.dart';

class NovoVendedorPage extends StatefulWidget {
  const NovoVendedorPage({super.key});

  @override
  State<NovoVendedorPage> createState() => _NovoVendedorPageState();
}

class _NovoVendedorPageState extends State<NovoVendedorPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> ctrls = {
    'codigo': TextEditingController(),
    'nome': TextEditingController(),
    'senha': TextEditingController(),
  };
  bool ativo = true;
  bool carregando = false;

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (carregando) return;

    setState(() => carregando = true);

    final vendedor = <String, dynamic>{
      'codigo': ctrls['codigo']!.text.trim(),
      'nome': ctrls['nome']!.text.trim(),
      'senha': ctrls['senha']!.text,
      'ativo': ativo ? 1 : 0, // SQLite usa int (1/0)
    };

    String msg = '';
    bool sucessoLocal = false;
    bool sucessoRemoto = false;

    // 1) Salva LOCAL no SQLite
    try {
      final db = await getDb();
      await db.insert(
        'vendedores',
        vendedor,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      sucessoLocal = true;
    } catch (e) {
      msg = 'Erro ao salvar localmente: $e';
    }

    // 2) Tenta sincronizar ONLINE (Supabase)
    if (sucessoLocal) {
      try {
        await inserirVendedorSupabase({
          ...vendedor,
          // No Supabase a coluna "ativo" costuma ser bool; converte:
          'ativo': ativo,
        });
        sucessoRemoto = true;
      } catch (_) {
        // Mantém silencioso; tratamos a mensagem abaixo
      }
    }

    if (!mounted) return;
    setState(() => carregando = false);

    if (sucessoLocal && sucessoRemoto) {
      _showSnack('Vendedor cadastrado e sincronizado!', sucesso: true, fechar: true);
    } else if (sucessoLocal && !sucessoRemoto) {
      _showSnack('Vendedor cadastrado localmente.\nSincronização pendente.', sucesso: false, fechar: true);
    } else {
      _showSnack(msg.isNotEmpty ? msg : 'Erro ao cadastrar vendedor.', sucesso: false);
    }
  }

  void _showSnack(String msg, {required bool sucesso, bool fechar = false}) {
    final snack = SnackBar(
      content: Text(msg),
      backgroundColor: sucesso ? milkdimOrange : milkdimDarkOrange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: const Duration(seconds: 2),
    );
    ScaffoldMessenger.of(context).showSnackBar(snack);
    if (fechar) {
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) Navigator.pop(context, true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        title: const Text('Novo Vendedor', style: TextStyle(color: milkdimOrange)),
        backgroundColor: milkdimWhite,
        iconTheme: const IconThemeData(color: milkdimOrange),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _campo(
                label: 'Código',
                ctrl: ctrls['codigo']!,
                validator: (v) => v == null || v.trim().isEmpty ? 'Informe o código!' : null,
                tipo: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _campo(
                label: 'Nome',
                ctrl: ctrls['nome']!,
                validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome!' : null,
              ),
              const SizedBox(height: 16),
              _campo(
                label: 'Senha',
                ctrl: ctrls['senha']!,
                validator: (v) => v == null || v.isEmpty ? 'Informe a senha!' : null,
                obscure: true,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: ativo,
                title: const Text('Ativo', style: TextStyle(color: milkdimDarkOrange)),
                activeColor: milkdimOrange,
                onChanged: carregando ? null : (v) => setState(() => ativo = v),
              ),
              const SizedBox(height: 32),
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
                  icon: const Icon(Icons.save, color: milkdimYellow),
                  label: const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.bold, color: milkdimYellow, fontSize: 20),
                  ),
                  onPressed: _salvar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo({
    required String label,
    required TextEditingController ctrl,
    String? Function(String?)? validator,
    TextInputType tipo = TextInputType.text,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: tipo,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: milkdimDarkOrange),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        // substitui withOpacity (deprecated)
        fillColor: milkdimYellow.withValues(alpha: 0.09),
      ),
    );
  }
}
