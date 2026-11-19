// lib/widgets/pedido_ui.dart
//
// Peças visuais comuns ao "Fazer Pedido" e ao "Editar Pedido": selo de recência
// do cliente, cartão de produto com quantidade, linha de informação e o
// conteúdo do resumo. Só apresentação: nenhuma regra de pedido mora aqui.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import '../utils/moeda.dart';

/// Recência do último pedido do cliente: < 15 dias, até 30 dias, mais de 30, nunca.
enum NivelRecencia { nenhum, recente, atencao, atrasado }

NivelRecencia classificarRecencia(DateTime? ultimo) {
  if (ultimo == null) return NivelRecencia.nenhum;
  final now = DateTime.now().toUtc();
  int days = now.difference(ultimo.toUtc()).inDays;
  if (days < 0) days = 0;
  if (days < 15) return NivelRecencia.recente;
  if (days <= 30) return NivelRecencia.atencao;
  return NivelRecencia.atrasado;
}

extension NivelRecenciaVisual on NivelRecencia {
  MdTipo get tipo => switch (this) {
        NivelRecencia.recente => MdTipo.sucesso,
        NivelRecencia.atencao => MdTipo.atencao,
        NivelRecencia.atrasado => MdTipo.erro,
        NivelRecencia.nenhum => MdTipo.neutro,
      };

  IconData get icone => switch (this) {
        NivelRecencia.recente => Icons.check_circle_outline,
        NivelRecencia.atencao => Icons.schedule,
        NivelRecencia.atrasado => Icons.warning_amber_rounded,
        NivelRecencia.nenhum => Icons.do_not_disturb_on_outlined,
      };
}

/// Selo com a data do último pedido do cliente (ou "Nunca").
class SeloUltimoPedido extends StatelessWidget {
  final DateTime? ultimoPedido;
  final bool comHora;

  const SeloUltimoPedido(
      {super.key, required this.ultimoPedido, this.comHora = false});

  @override
  Widget build(BuildContext context) {
    final nivel = classificarRecencia(ultimoPedido);
    final texto = ultimoPedido == null
        ? 'Nunca'
        : DateFormat(comHora ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy')
            .format(ultimoPedido!.toLocal());
    return MdStatusChip(tipo: nivel.tipo, texto: texto, icone: nivel.icone);
  }
}

/// Linha "rótulo  valor" do resumo; valor vazio aparece como "—".
class LinhaInfo extends StatelessWidget {
  final String rotulo;
  final String valor;

  const LinhaInfo(this.rotulo, this.valor, {super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final vazio = valor.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(rotulo,
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          ),
          const SizedBox(width: MdSpace.sm),
          Expanded(
            child: Text(
              vazio ? '—' : valor,
              style: vazio
                  ? tt.bodyMedium!.copyWith(color: MdColors.textMuted)
                  : tt.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de produto com nome, preço e campo de quantidade.
class ProdutoQtdTile extends StatelessWidget {
  final String nome;
  final double preco;
  final int quantidade;
  final TextEditingController controller;
  final bool habilitado;
  final ValueChanged<String>? onChanged;

  const ProdutoQtdTile({
    super.key,
    required this.nome,
    required this.preco,
    required this.quantidade,
    required this.controller,
    required this.habilitado,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final noCarrinho = quantidade > 0;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MdRadius.card),
        side: BorderSide(
          color: noCarrinho ? MdColors.primary : MdColors.border,
          width: noCarrinho ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: MdSpace.lg, vertical: MdSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall!.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatarReais(preco),
                    style: tt.bodyMedium!.copyWith(
                      color: MdColors.primaryStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MdSpace.md),
            SizedBox(
              width: 88,
              child: TextField(
                controller: controller,
                enabled: habilitado,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: tt.titleMedium,
                decoration: const InputDecoration(
                  labelText: 'Qtd',
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: MdSpace.sm, vertical: 14),
                ),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item do resumo: nome, quantidade e subtotal.
typedef ItemResumo = ({String nome, int quantidade, double subtotal});

/// Conteúdo da folha "Resumo do Pedido" (dados do cliente, itens, total,
/// assinatura e os botões Salvar/Finalizar). Os callbacks vêm da página.
class ResumoPedido extends StatelessWidget {
  final String numero;
  final String cliente;
  final DateTime? ultimoPedido;

  /// Demais campos do cliente, na ordem em que aparecem.
  final List<(String, String)> campos;
  final String vendedor;
  final List<ItemResumo> itens;
  final double total;
  final Uint8List? assinatura;
  final bool ocupado;
  final VoidCallback onAssinar;
  final VoidCallback onSalvar;
  final VoidCallback onFinalizar;

  const ResumoPedido({
    super.key,
    required this.numero,
    required this.cliente,
    required this.ultimoPedido,
    required this.campos,
    required this.vendedor,
    required this.itens,
    required this.total,
    required this.assinatura,
    required this.ocupado,
    required this.onAssinar,
    required this.onSalvar,
    required this.onFinalizar,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Resumo do Pedido',
            style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: MdSpace.lg),
        LinhaInfo('Nº Pedido', numero),
        LinhaInfo('Cliente', cliente),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text('Último pedido',
                    style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
              ),
              const SizedBox(width: MdSpace.sm),
              Flexible(
                  child: SeloUltimoPedido(
                      ultimoPedido: ultimoPedido, comHora: true)),
            ],
          ),
        ),
        for (final (rotulo, valor) in campos) LinhaInfo(rotulo, valor),
        LinhaInfo('Vendedor', vendedor),
        const SizedBox(height: MdSpace.md),
        const Divider(),
        const SizedBox(height: MdSpace.sm),
        for (final it in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MdSpace.xs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.nome,
                          style: tt.bodyLarge!
                              .copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        formatarReais(it.subtotal),
                        style:
                            tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MdSpace.sm),
                Text(
                  'x${it.quantidade}',
                  style:
                      tt.titleMedium!.copyWith(color: MdColors.primaryStrong),
                ),
              ],
            ),
          ),
        const SizedBox(height: MdSpace.sm),
        const Divider(),
        const SizedBox(height: MdSpace.md),
        Row(
          children: [
            Expanded(child: Text('Total', style: tt.titleMedium)),
            Text(
              formatarReais(total),
              style: tt.titleLarge!.copyWith(color: MdColors.primaryStrong),
            ),
          ],
        ),
        const SizedBox(height: MdSpace.lg),
        Text('Assinatura', style: tt.titleSmall),
        const SizedBox(height: MdSpace.sm),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.all(MdSpace.xs),
                decoration: BoxDecoration(
                  color: assinatura == null
                      ? MdColors.background
                      : MdColors.surface,
                  border: Border.all(color: MdColors.border),
                  borderRadius: BorderRadius.circular(MdRadius.field),
                ),
                alignment: Alignment.center,
                child: assinatura == null
                    ? Text(
                        'Não assinada',
                        style: tt.bodyMedium!.copyWith(
                          color: MdColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Image.memory(assinatura!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: MdSpace.md),
            OutlinedButton.icon(
              onPressed: ocupado ? null : onAssinar,
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Assinar'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg),
              ),
            ),
          ],
        ),
        const SizedBox(height: MdSpace.xl),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ocupado ? null : onSalvar,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
              ),
            ),
            const SizedBox(width: MdSpace.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: ocupado ? null : onFinalizar,
                icon: ocupado
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: MdColors.textMuted,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Icon(Icons.check),
                label: const Text('Finalizar'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Barra fixa no rodapé com o botão "Resumo R$ ...".
class BarraResumo extends StatelessWidget {
  final double total;
  final VoidCallback? onPressed;

  const BarraResumo({super.key, required this.total, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MdColors.surface,
        border: Border(top: BorderSide(color: MdColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              MdSpace.lg, MdSpace.md, MdSpace.lg, MdSpace.md),
          // Align com heightFactor 1: a barra fica só da altura do botão.
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text('Resumo ${formatarReais(total)}'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo "Buscar cliente por nome" (a página faz a busca e o preenchimento).
class ConteudoBuscaCliente extends StatelessWidget {
  final TextEditingController controller;
  final List<Map<String, dynamic>> resultados;
  final VoidCallback onBuscar;
  final ValueChanged<Map<String, dynamic>> onEscolher;

  const ConteudoBuscaCliente({
    super.key,
    required this.controller,
    required this.resultados,
    required this.onBuscar,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => onBuscar(),
        ),
        const SizedBox(height: MdSpace.md),
        // Flexível: com o teclado aberto num celular pequeno a lista encolhe
        // em vez de passar da borda do diálogo.
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SizedBox(
              width: double.maxFinite,
              child: resultados.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum cliente encontrado',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(color: MdColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: resultados.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (ctx, i) {
                        final cli = resultados[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: MdSpace.sm),
                          leading: const Icon(Icons.person_outline),
                          title: Text(cli['nome'] ?? ''),
                          subtitle: Text(
                            (cli['cpf_cnpj'] ?? '') +
                                (cli['telefone'] != null
                                    ? " • ${cli['telefone']}"
                                    : ""),
                          ),
                          onTap: () => onEscolher(cli),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
