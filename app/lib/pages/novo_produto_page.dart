import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../utils/supabase_helper.dart';

class NovoProdutoPage extends StatefulWidget {
  const NovoProdutoPage({super.key});

  @override
  State<NovoProdutoPage> createState() => _NovoProdutoPageState();
}

class _NovoProdutoPageState extends State<NovoProdutoPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> ctrls = {
    'nome': TextEditingController(),
    'preco': TextEditingController(),
    'descricao': TextEditingController(),
    'ativo': TextEditingController(text: 'true'),
  };
  bool carregando = false;

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => carregando = true);

    final produto = <String, dynamic>{
      'nome': ctrls['nome']!.text.trim(),
      'preco': double.tryParse(ctrls['preco']!.text.replaceAll(',', '.')) ?? 0.0,
      'descricao': ctrls['descricao']!.text.trim(),
      'ativo': ctrls['ativo']!.text == 'true',
      'datahora': DateTime.now().toIso8601String(),
    };

    try {
      await inserirProdutoSupabase(produto);
      _showSnack('Produto cadastrado com sucesso!', sucesso: true, fechar: true);
    } catch (e) {
      _showSnack('Erro ao salvar produto: $e', sucesso: false);
    }
    setState(() => carregando = false);
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
      Future.delayed(const Duration(milliseconds: 1800), () => Navigator.pop(context));
    }
  }

  @override
  void dispose() {
    for (var c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        title: const Text('Novo Produto', style: TextStyle(color: milkdimOrange)),
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
                'Nome',
                ctrls['nome']!,
                validator: (v) => v == null || v.isEmpty ? 'Informe o nome!' : null,
              ),
              const SizedBox(height: 16),
              _campo(
                'Preço',
                ctrls['preco']!,
                tipo: TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Informe o preço!';
                  final val = double.tryParse(v.replaceAll(',', '.'));
                  if (val == null || val <= 0) return 'Preço inválido!';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _campo('Descrição', ctrls['descricao']!, linhas: 2),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Produto Ativo', style: TextStyle(color: milkdimDarkOrange)),
                value: ctrls['ativo']!.text == 'true',
                onChanged: carregando
                    ? null
                    : (val) => setState(() => ctrls['ativo']!.text = val ? 'true' : 'false'),
                activeColor: milkdimOrange,
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
                  onPressed: carregando ? null : _salvar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo(
      String label,
      TextEditingController ctrl, {
        String? Function(String?)? validator,
        TextInputType tipo = TextInputType.text,
        int linhas = 1,
      }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      keyboardType: tipo,
      maxLines: linhas,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: milkdimDarkOrange),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: milkdimYellow.withOpacity(0.09),
      ),
    );
  }
}
