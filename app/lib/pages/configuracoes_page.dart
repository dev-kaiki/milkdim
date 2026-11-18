// lib/pages/configuracoes_page.dart
//
// Sem PIN: só "Sincronizar" e "Cadastrar novo cliente". Cadastro de vendedor e
// de produto ficam no app de controle.
import 'package:flutter/material.dart';
import '../utils/colors.dart';
import 'novo_cliente_page.dart';
import '../utils/supabase_helper.dart';
import '../utils/auth.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  bool _sincronizando = false;

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);

    final vendedor = await vendedorLocal();
    final codigo = vendedor?['codigo']?.toString() ?? '';
    var sucesso = false;
    try {
      sucesso = codigo.isNotEmpty &&
          await sincronizarTudoERegistrar(vendedorCodigo: codigo);
    } catch (_) {}

    if (!mounted) return;
    _showSnack(
      sucesso
          ? 'Sincronização realizada com sucesso!'
          : 'Erro ao sincronizar alguns dados!',
      sucesso: sucesso,
    );

    if (!mounted) return;
    setState(() => _sincronizando = false);
  }

  void _showSnack(String msg, {bool sucesso = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: sucesso ? milkdimOrange : milkdimDarkOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _adicionarCliente() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NovoClientePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        title: const Text('Configurações', style: TextStyle(color: milkdimOrange)),
        backgroundColor: milkdimWhite,
        iconTheme: const IconThemeData(color: milkdimOrange),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Card(
              color: milkdimWhite,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ListTile(
                leading: const Icon(Icons.sync, color: milkdimOrange, size: 34),
                title: const Text(
                  'Sincronizar dados com servidor',
                  style: TextStyle(fontWeight: FontWeight.bold, color: milkdimDarkOrange),
                ),
                subtitle: const Text('Clientes, produtos e pedidos'),
                onTap: _sincronizando ? null : _sincronizar,
                trailing: _sincronizando
                    ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: milkdimOrange,
                    strokeWidth: 3,
                  ),
                )
                    : const Icon(Icons.cloud_sync, color: milkdimOrange),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: milkdimWhite,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ListTile(
                leading: const Icon(Icons.person_add, color: milkdimDarkOrange, size: 34),
                title: const Text(
                  'Cadastrar novo cliente',
                  style: TextStyle(fontWeight: FontWeight.bold, color: milkdimOrange),
                ),
                onTap: _adicionarCliente,
                trailing: const Icon(Icons.arrow_forward_ios, color: milkdimOrange, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
