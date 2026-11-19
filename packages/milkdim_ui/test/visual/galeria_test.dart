// Captura da galeria de componentes em build/visual/ (revisão humana, sem golden).
// Roda com o resto dos testes; só ela: flutter test --tags visual
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:milkdim_ui/testing/md_visual.dart';

void main() {
  setUpAll(carregarFontesReais);

  // No próprio pacote o logo não tem o prefixo packages/milkdim_ui no bundle de teste,
  // então a galeria lê o arquivo direto do disco.
  final logo = FileImage(File('assets/logo.jpg'));

  testWidgets('galeria (componentes)', (tester) async {
    await capturar(tester, _Galeria(logo: logo), 'galeria');
  });

  testWidgets('galeria (estilos do tema)', (tester) async {
    await capturar(tester, _Estilos(logo: logo), 'galeria_estilos');
  });
}

class _Galeria extends StatelessWidget {
  final ImageProvider logo;
  const _Galeria({required this.logo});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: MdLogoTitle(logo: logo), actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined)),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(MdSpace.lg),
        children: [
          MdCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Olá, João', style: tt.titleLarge),
                  const SizedBox(height: MdSpace.xs),
                  Text('Vendedor 0001', style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
                ]),
              ),
              const MdStatusChip(
                  tipo: MdTipo.sucesso, texto: 'Em dia', icone: Icons.cloud_done_outlined),
            ]),
          ),
          const SizedBox(height: MdSpace.md),
          MdBanner(
            tipo: MdTipo.atencao,
            icone: Icons.cloud_upload_outlined,
            texto: '2 pedidos aguardando envio',
            acao: TextButton(onPressed: () {}, child: const Text('Enviar agora')),
          ),
          const SizedBox(height: MdSpace.lg),
          MdActionTile(
            icone: Icons.add_shopping_cart,
            titulo: 'Novo pedido',
            subtitulo: 'Escolher cliente e produtos',
            destaque: true,
            onTap: () {},
          ),
          const SizedBox(height: MdSpace.md),
          MdActionTile(
            icone: Icons.receipt_long_outlined,
            titulo: 'Meus pedidos',
            subtitulo: 'Ver, editar e reenviar',
            onTap: () {},
          ),
          const SizedBox(height: MdSpace.md),
          const MdActionTile(icone: Icons.block, titulo: 'Ação desabilitada', onTap: null),
          const SizedBox(height: MdSpace.lg),
          MdSectionHeader(
            titulo: 'Status',
            trailing: TextButton(onPressed: () {}, child: const Text('Ver todos')),
          ),
          const Wrap(spacing: MdSpace.sm, runSpacing: MdSpace.sm, children: [
            MdStatusChip(tipo: MdTipo.sucesso, texto: 'Enviado'),
            MdStatusChip(tipo: MdTipo.atencao, texto: 'Aguardando', icone: Icons.schedule),
            MdStatusChip(tipo: MdTipo.erro, texto: 'Falhou', icone: Icons.error_outline),
            MdStatusChip(tipo: MdTipo.info, texto: 'Novo'),
            MdStatusChip(tipo: MdTipo.neutro, texto: 'Inativo'),
          ]),
          const SizedBox(height: MdSpace.lg),
          const MdBanner(tipo: MdTipo.info, texto: 'Sincronizado há 2 dias.'),
          const SizedBox(height: MdSpace.sm),
          const MdBanner(tipo: MdTipo.erro, texto: 'Erro ao sincronizar dados.'),
          const SizedBox(height: MdSpace.sm),
          const MdBanner(tipo: MdTipo.sucesso, texto: 'Sincronização realizada!'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Clientes'),
        ],
      ),
    );
  }
}

class _Estilos extends StatefulWidget {
  final ImageProvider logo;
  const _Estilos({required this.logo});

  @override
  State<_Estilos> createState() => _EstilosState();
}

class _EstilosState extends State<_Estilos> {
  final _busca = TextEditingController(text: 'padaria');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMdSnack(context, 'Pedido salvo. Será enviado quando houver internet.');
    });
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estilos do tema')),
      body: ListView(
        padding: const EdgeInsets.all(MdSpace.lg),
        children: [
          MdSearchField(controller: _busca, hint: 'Buscar cliente'),
          const SizedBox(height: MdSpace.md),
          const TextField(
              decoration:
                  InputDecoration(labelText: 'Nome do cliente', hintText: 'Ex.: Padaria Central')),
          const SizedBox(height: MdSpace.md),
          const TextField(
            decoration: InputDecoration(labelText: 'CNPJ', errorText: 'CNPJ inválido'),
          ),
          const SizedBox(height: MdSpace.lg),
          Row(children: [
            Expanded(child: FilledButton(onPressed: () {}, child: const Text('Salvar'))),
            const SizedBox(width: MdSpace.md),
            Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Cancelar'))),
          ]),
          const SizedBox(height: MdSpace.md),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
            ),
            const SizedBox(width: MdSpace.md),
            const Expanded(child: FilledButton(onPressed: null, child: Text('Desabilitado'))),
          ]),
          const SizedBox(height: MdSpace.sm),
          Row(children: [
            TextButton(onPressed: () {}, child: const Text('Texto')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MdColors.danger),
              onPressed: () {},
              child: const Text('Excluir'),
            ),
            const Spacer(),
            Switch(value: true, onChanged: (_) {}),
            Checkbox(value: true, onChanged: (_) {}),
          ]),
          const SizedBox(height: MdSpace.md),
          Wrap(spacing: MdSpace.sm, children: [
            FilterChip(label: const Text('Ativos'), selected: true, onSelected: (_) {}),
            FilterChip(label: const Text('Inativos'), selected: false, onSelected: (_) {}),
            const Chip(label: Text('Rota 3')),
          ]),
          const SizedBox(height: MdSpace.md),
          const LinearProgressIndicator(value: 0.6),
          const SizedBox(height: MdSpace.md),
          const MdCard(
            padding: EdgeInsets.zero,
            child: MdEmptyState(
              icone: Icons.inbox_outlined,
              titulo: 'Nenhum pedido ainda',
              texto: 'Os pedidos feitos aparecem aqui.',
            ),
          ),
          const SizedBox(height: MdSpace.md),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Padaria Central'),
                subtitle: const Text('Último pedido há 3 dias'),
                trailing: const MdStatusChip(tipo: MdTipo.sucesso, texto: 'Ativo'),
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Mercado Bom Preço'),
                subtitle: const Text('Último pedido há 40 dias'),
                trailing: const MdStatusChip(tipo: MdTipo.erro, texto: 'Parado'),
                onTap: () {},
              ),
            ]),
          ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
    );
  }
}
