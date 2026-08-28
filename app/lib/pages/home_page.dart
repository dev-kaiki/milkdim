// lib/pages/home_page.dart
//
// • Teste de conexão faz um select simples no Supabase.
// • "Visualizar Pedidos" passa o vendedorCodigo para filtrar.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/colors.dart';
import 'pedido_page.dart';        // <- IMPORTA O WIDGET PedidoPage
import 'pedidos_page.dart';
import 'configuracoes_page.dart';

class HomePage extends StatelessWidget {
  final Map<String, dynamic> vendedor;
  static const String _adminPin = '753159';

  const HomePage({super.key, required this.vendedor});

  // Checagem simples no Supabase
  static Future<bool> supabaseDnsOk() async {
    try {
      // Em supabase_flutter ^2.x já “executa” ao aguardar o builder.
      await Supabase.instance.client.from('clientes').select('id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pedirSenhaConfiguracao(BuildContext context) async {
    final senhaCtrl = TextEditingController();
    bool senhaErrada = false;
    bool testandoConexao = false;
    bool? dnsOk;

    final aprovado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            backgroundColor: milkdimWhite,
            title: const Text('Acesso restrito', style: TextStyle(color: milkdimOrange)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: senhaCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Senha de administrador',
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: senhaErrada ? 'Senha incorreta' : null,
                  ),
                  onSubmitted: (_) {
                    final ok = senhaCtrl.text == _adminPin;
                    if (!ok) {
                      setStateDialog(() => senhaErrada = true);
                    } else {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: testandoConexao
                            ? null
                            : () async {
                          setStateDialog(() => testandoConexao = true);
                          dnsOk = await HomePage.supabaseDnsOk();
                          setStateDialog(() => testandoConexao = false);
                        },
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Testar conexão Supabase'),
                      ),
                    ),
                  ],
                ),
                if (dnsOk != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        dnsOk! ? Icons.check_circle : Icons.error,
                        color: dnsOk! ? Colors.green : milkdimDarkOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dnsOk!
                              ? 'Conseguimos consultar o Supabase.'
                              : 'Falha ao consultar o Supabase.',
                          style: TextStyle(
                            color: dnsOk! ? Colors.green[700] : milkdimDarkOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Cancelar', style: TextStyle(color: milkdimDarkOrange)),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: milkdimOrange,
                  foregroundColor: milkdimWhite,
                ),
                child: const Text('Entrar'),
                onPressed: () {
                  final ok = senhaCtrl.text == _adminPin;
                  if (!ok) {
                    setStateDialog(() => senhaErrada = true);
                  } else {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    // Se estiver em Flutter >= 3.7 o context.mounted existe; senão, pode remover.
    if (!context.mounted) return;

    if (aprovado == true) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
      );
    } else if (aprovado == false && senhaCtrl.text.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Senha incorreta!'),
          backgroundColor: milkdimDarkOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendedorCodigo = vendedor['codigo']?.toString() ?? '';

    return Scaffold(
      backgroundColor: milkdimWhite,
      appBar: AppBar(
        backgroundColor: milkdimWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: milkdimOrange),
        title: Row(
          children: [
            Image.asset('assets/logo.jpg', height: 36),
            const SizedBox(width: 12),
            const Text(
              'MilkDim',
              style: TextStyle(
                color: milkdimOrange,
                fontWeight: FontWeight.bold,
                fontSize: 25,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: milkdimDarkOrange),
            onPressed: () => _pedirSenhaConfiguracao(context),
            tooltip: "Configurações",
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PedidoPage(vendedor: vendedor),
                    ),
                  );
                },
                icon: const Icon(Icons.add_shopping_cart, color: milkdimWhite, size: 30),
                label: const Text(
                  'Novo Pedido',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: milkdimOrange,
                  foregroundColor: milkdimWhite,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(fontSize: 21),
                ),
              ),
              const SizedBox(height: 26),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PedidosPage(vendedorCodigo: vendedorCodigo),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt, color: milkdimDarkOrange, size: 30),
                label: const Text(
                  'Visualizar Pedidos',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: milkdimYellow.withOpacity(0.45),
                  foregroundColor: milkdimDarkOrange,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 3,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: const TextStyle(fontSize: 21),
                ),
              ),
              const SizedBox(height: 34),
              const Text(
                'Versão 1.0 • MilkDim Alimentos',
                style: TextStyle(fontSize: 14, color: milkdimDarkOrange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
