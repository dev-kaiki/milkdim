// lib/widgets/detalhe_pedido.dart
//
// Detalhe do pedido (folha de baixo), usado pelas abas Pedidos e Produção:
// dados formatados (`Pedido`) e um bloco com **todas as colunas** (JSON bruto).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pedido.dart';

/// Linha crua do Supabase (todas as colunas) e o `Pedido` dela.
typedef DetalheDoPedido = ({Map<String, dynamic> raw, Pedido parsed});

/// Busca 1) linha crua do Supabase (todas as colunas) e
/// 2) mapeia para `Pedido` para renderização bonita.
Future<DetalheDoPedido> buscarDetalhePedido(int id) async {
  final raw =
      await Supabase.instance.client.from('pedidos').select('*').eq('id', id).single();
  final map = Map<String, dynamic>.from(raw as Map);
  return (raw: map, parsed: Pedido.fromMap(map));
}

final _dateFmt = DateFormat('dd/MM HH:mm');

/// "dd/MM HH:mm" de um ISO-8601; '-' se vazio ou ilegível.
String fmtDataPedido(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '-';
  return _dateFmt.format(dt.toLocal());
}

String fmtMoedaPedido(num? v) {
  if (v == null) return 'R\$ 0,00';
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ $s';
}

/// Em aberto = info, finalizado = sucesso, cancelado = neutro, demais = atenção.
MdTipo tipoDaSituacao(String status) {
  switch (status) {
    case 'salvo':
      return MdTipo.info;
    case 'finalizado':
      return MdTipo.sucesso;
    case 'cancelado':
      return MdTipo.neutro;
    default:
      return MdTipo.atencao;
  }
}

Widget chipSituacao(Pedido p) =>
    MdStatusChip(tipo: tipoDaSituacao(p.status), texto: p.situacaoTexto);

String vendedorTextoPedido(Pedido p) =>
    (p.vendedorCodigo ?? '') +
    ((p.vendedorNome ?? '').isNotEmpty ? ' (${p.vendedorNome})' : '');

bool temVendedorPedido(Pedido p) =>
    (p.vendedorCodigo ?? '').isNotEmpty || (p.vendedorNome ?? '').isNotEmpty;

/// Abre o detalhe do pedido [p] (busca a linha completa no servidor).
/// - [buscar]: troca a busca (testes); nulo usa [buscarDetalhePedido].
/// - [apagar]: mostra o botão "Apagar pedido" e o chama; devolve true se
///   apagou (a folha fecha). Nulo: sem o botão.
void abrirDetalhesPedido(
  BuildContext context,
  Pedido p, {
  Future<DetalheDoPedido> Function(int id)? buscar,
  Future<bool> Function(Pedido p)? apagar,
}) {
  Future<DetalheDoPedido?> carregar() async {
    try {
      return await (buscar ?? buscarDetalhePedido)(p.id);
    } catch (e) {
      if (!context.mounted) return null;
      showMdSnack(context, 'Erro ao carregar detalhes do pedido #${p.id}: $e',
          tipo: MdTipo.erro);
      return null;
    }
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MdSpace.xl, 0, MdSpace.xl, MdSpace.lg),
          child: FutureBuilder<DetalheDoPedido?>(
            future: carregar(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snap.data;
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Não foi possível carregar os detalhes.'),
                );
              }
              return _FolhaDetalhe(
                raw: data.raw,
                ped: data.parsed,
                contextoDaAba: context,
                apagar: apagar,
              );
            },
          ),
        ),
      );
    },
  );
}

class _FolhaDetalhe extends StatelessWidget {
  const _FolhaDetalhe({
    required this.raw,
    required this.ped,
    required this.contextoDaAba,
    required this.apagar,
  });

  final Map<String, dynamic> raw;
  final Pedido ped;

  /// Onde aparecem os avisos de "copiado".
  final BuildContext contextoDaAba;
  final Future<bool> Function(Pedido p)? apagar;

  Future<void> _copy(String label, String? value) async {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!contextoDaAba.mounted) return;
    showMdSnack(contextoDaAba, '$label copiado');
  }

  Widget _rotulo(BuildContext context, String label) => SizedBox(
        width: 140,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: MdColors.textMuted),
        ),
      );

  /// Bloco monoespaçado (JSON) selecionável.
  Widget _blocoCodigo(String texto) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MdRadius.field),
          color: MdColors.background,
          border: Border.all(color: MdColors.border),
        ),
        padding: const EdgeInsets.all(MdSpace.md),
        child: SelectableText(
          texto,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.3),
        ),
      );

  // Mostra um rótulo + valor, aceitando qualquer tipo.
  // Se for Map/List, mostra um bloco JSON identado e selecionável.
  Widget _infoRow(BuildContext context, String label, Object? value, {bool dense = false}) {
    String v;
    bool isJsonBlock = false;

    if (value == null) {
      v = '—';
    } else if (value is String) {
      v = value.trim().isEmpty ? '—' : value;
    } else if (value is bool) {
      v = value ? 'Sim' : 'Não';
    } else if (value is num) {
      v = value.toString();
    } else if (value is DateTime) {
      v = _dateFmt.format(value.toLocal());
    } else if (value is Map || value is Iterable) {
      v = const JsonEncoder.withIndent('  ').convert(value);
      isJsonBlock = true;
    } else {
      v = value.toString();
    }

    final Widget valueWidget = isJsonBlock ? _blocoCodigo(v) : Text(v);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rotulo(context, label),
          const SizedBox(width: MdSpace.sm),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _infoRowWidget(BuildContext context, String label, Widget value, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rotulo(context, label),
          const SizedBox(width: MdSpace.sm),
          Expanded(child: value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(raw);
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.25,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) {
        final clienteTitulo =
            (ped.clienteNome ?? ped.clienteNomeFantasia ?? 'Cliente').toString();
        return ListView(
          controller: controller,
          children: [
            // HEADER
            Row(
              children: [
                Expanded(
                  child: Text(clienteTitulo, style: tt.titleLarge),
                ),
                if (apagar != null)
                  IconButton(
                    tooltip: 'Apagar pedido',
                    color: MdColors.danger,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final deleted = await apagar!(ped);
                      if (deleted && context.mounted) {
                        Navigator.of(context).pop(); // fecha a folha de detalhes
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: MdSpace.sm),
            Wrap(
              spacing: MdSpace.sm,
              runSpacing: MdSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                chipSituacao(ped),
                if ((ped.numero ?? '').isNotEmpty) Chip(label: Text('Nº ${ped.numero}')),
                Chip(label: Text('ID ${ped.id}')),
                Chip(label: Text('Total: ${fmtMoedaPedido(ped.total)}')),
                Chip(label: Text('Itens: ${ped.totalItens}')),
                if (temVendedorPedido(ped))
                  Chip(
                    avatar: const Icon(Icons.badge_outlined, size: 18),
                    label: Text(vendedorTextoPedido(ped)),
                  ),
                Chip(label: Text('Quando: ${fmtDataPedido(ped.datahora)}')),
              ],
            ),
            const SizedBox(height: MdSpace.lg),
            const Divider(),

            // ITENS
            const SizedBox(height: MdSpace.md),
            const MdSectionHeader(titulo: 'Itens do pedido'),
            // Lista em vez de tabela: com nomes longos ("1100g Chocolate ...") a tabela
            // rolava de lado e escondia a quantidade e o subtotal.
            MdCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < ped.itens.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ItemPedidoLinha(item: ped.itens[i]),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: MdSpace.md, right: MdSpace.xs),
                child: Text('Total: ${fmtMoedaPedido(ped.total)}', style: tt.titleMedium),
              ),
            ),

            // CLIENTE
            const SizedBox(height: MdSpace.lg),
            const Divider(),
            const SizedBox(height: MdSpace.md),
            const MdSectionHeader(titulo: 'Dados do cliente'),
            _infoRow(context, 'Código (ID)', ped.clienteId, dense: true),
            _infoRow(context, 'Nome', ped.clienteNome, dense: true),
            _infoRow(context, 'Nome fantasia', ped.clienteNomeFantasia, dense: true),
            _infoRowWidget(
              context,
              'Telefone/WhatsApp',
              Wrap(spacing: MdSpace.sm, runSpacing: MdSpace.sm, children: [
                if ((ped.clienteTelefone ?? '').trim().isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.call_outlined, size: 18),
                    label: Text(ped.clienteTelefone!),
                    onPressed: () => _copy('Telefone', ped.clienteTelefone),
                  ),
                if ((ped.clienteWhatsapp ?? '').trim().isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.sms, size: 18),
                    label: Text(ped.clienteWhatsapp!),
                    onPressed: () => _copy('WhatsApp', ped.clienteWhatsapp),
                  ),
              ]),
              dense: true,
            ),
            _infoRow(context, 'Email', ped.clienteEmail, dense: true),
            _infoRow(context, 'Endereço', ped.clienteEndereco, dense: true),
            _infoRow(context, 'Cidade', ped.clienteCidade, dense: true),
            _infoRow(context, 'CPF/CNPJ', ped.clienteCpfCnpj, dense: true),
            _infoRow(context, 'Inscr. Estadual', ped.clienteInscEstadual, dense: true),
            _infoRow(context, 'CEP', ped.clienteCep, dense: true),
            _infoRow(context, 'Anotação', ped.clienteAnotacao),

            // VENDEDOR
            const SizedBox(height: MdSpace.lg),
            const Divider(),
            const SizedBox(height: MdSpace.md),
            const MdSectionHeader(titulo: 'Vendedor'),
            _infoRow(context, 'Código', ped.vendedorCodigo),
            _infoRow(context, 'Nome', ped.vendedorNome),

            // SITUAÇÃO / AUDITORIA
            const SizedBox(height: MdSpace.lg),
            const Divider(),
            const SizedBox(height: MdSpace.md),
            const MdSectionHeader(titulo: 'Situação'),
            _infoRow(context, 'Situação', ped.situacaoTexto),
            _infoRow(context, 'Enviado em', ped.enviadoEm),
            _infoRow(context, 'Alterado em', ped.alteradoEm),
            _infoRow(
              context,
              'Finalizado em',
              ped.finalizadoEm == null ? null : _dateFmt.format(ped.finalizadoEm!.toLocal()),
            ),
            _infoRow(
              context,
              'Finalizado por',
              ped.finalizadoPor == null
                  ? null
                  : '${ped.finalizadoPor}${ped.finalizadoManual ? ' (manual)' : ''}',
            ),
            _infoRow(context, 'Cancelado em', ped.canceladoEm),
            _infoRow(context, 'Cancelado por', ped.canceladoPor),

            // DADOS BRUTOS / TODAS AS COLUNAS
            const SizedBox(height: MdSpace.lg),
            const Divider(),
            const SizedBox(height: MdSpace.md),
            MdSectionHeader(
              titulo: 'Dados brutos (todas as colunas)',
              trailing: IconButton(
                tooltip: 'Copiar JSON',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: jsonStr));
                  if (!context.mounted) return;
                  showMdSnack(context, 'JSON copiado para a área de transferência.');
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ),
            _blocoCodigo(jsonStr),
            const SizedBox(height: MdSpace.lg),
          ],
        );
      },
    );
  }
}

/// Uma linha de item: quantidade em destaque, nome (quebra linha se longo),
/// "N un × preço" embaixo e o subtotal à direita. Nada fica escondido.
class _ItemPedidoLinha extends StatelessWidget {
  final PedidoItem item;

  const _ItemPedidoLinha({required this.item});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final q = item.quantidade;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg, vertical: MdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Text(
              '$q×',
              style: tt.titleMedium!.copyWith(color: MdColors.primaryStrong),
            ),
          ),
          const SizedBox(width: MdSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nome.trim(), style: tt.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  '$q ${q == 1 ? 'unidade' : 'unidades'} × ${fmtMoedaPedido(item.preco)}',
                  style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: MdSpace.md),
          Text(fmtMoedaPedido(item.subtotal), style: tt.titleSmall),
        ],
      ),
    );
  }
}
