// lib/pages/configuracoes_page.dart
//
// Sem PIN: só "Sincronizar" e "Cadastrar novo cliente". Cadastro de vendedor e
// de produto ficam no app de controle.
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
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
    showMdSnack(context, msg, tipo: sucesso ? MdTipo.sucesso : MdTipo.erro);
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
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(MdSpace.lg),
        children: [
          MdContentWidth(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MdSectionHeader(titulo: 'Dados'),
                MdCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: MdSpace.lg, vertical: MdSpace.sm),
                    leading: const _IconeOpcao(Icons.sync),
                    title: const Text('Sincronizar dados com servidor'),
                    subtitle: const Text('Clientes, produtos e pedidos'),
                    onTap: _sincronizando ? null : _sincronizar,
                    trailing: _sincronizando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: MdSpace.lg),
                const MdSectionHeader(titulo: 'Clientes'),
                MdCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: MdSpace.lg, vertical: MdSpace.sm),
                    leading: const _IconeOpcao(Icons.person_add_alt_1_outlined),
                    title: const Text('Cadastrar novo cliente'),
                    onTap: _adicionarCliente,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ícone da opção num círculo laranja-claro (mesmo desenho do MdActionTile).
class _IconeOpcao extends StatelessWidget {
  final IconData icone;
  const _IconeOpcao(this.icone);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(color: MdColors.primarySoft, shape: BoxShape.circle),
      child: Icon(icone, color: MdColors.primaryStrong, size: 24),
    );
  }
}
