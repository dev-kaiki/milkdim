// lib/widgets/lista_adaptavel.dart
//
// Peças de layout das abas do Controle, montadas só com o tema e o milkdim_ui.
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

/// Largura útil a partir da qual as listas de cartões viram duas colunas.
const double larguraDuasColunas = 720;

/// Lista de cartões com "puxar para atualizar": uma coluna no celular e duas
/// colunas (cartões da mesma linha com a mesma altura) em telas largas.
class ListaAdaptavel extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Future<void> Function() onRefresh;

  /// Espaço extra no fim (ex.: para o FAB não cobrir o último cartão).
  final double espacoFinal;

  /// Falso força uma coluna só (ex.: linhas ricas de pedidos).
  final bool permitirDuasColunas;

  const ListaAdaptavel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onRefresh,
    this.espacoFinal = 0,
    this.permitirDuasColunas = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final padding = EdgeInsets.fromLTRB(
            MdSpace.lg, MdSpace.sm, MdSpace.lg, MdSpace.lg + espacoFinal);
        final duas = permitirDuasColunas && c.maxWidth >= larguraDuasColunas;

        final Widget lista;
        if (!duas) {
          lista = ListView.separated(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(height: MdSpace.md),
            itemBuilder: itemBuilder,
          );
        } else {
          final linhas = (itemCount + 1) ~/ 2;
          lista = ListView.separated(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: linhas,
            separatorBuilder: (_, __) => const SizedBox(height: MdSpace.md),
            itemBuilder: (context, linha) {
              final a = linha * 2;
              final b = a + 1;
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: itemBuilder(context, a)),
                    const SizedBox(width: MdSpace.md),
                    Expanded(
                      child: b < itemCount ? itemBuilder(context, b) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            },
          );
        }
        return RefreshIndicator(onRefresh: onRefresh, child: lista);
      },
    );
  }
}

/// Barra do topo das abas: busca + (em telas largas) ações à direita.
class BarraDaAba extends StatelessWidget {
  final Widget busca;
  final List<Widget> acoes;

  const BarraDaAba({super.key, required this.busca, this.acoes = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(MdSpace.lg, MdSpace.lg, MdSpace.lg, MdSpace.sm),
      child: Row(
        children: [
          Expanded(child: busca),
          for (final a in acoes) ...[const SizedBox(width: MdSpace.md), a],
        ],
      ),
    );
  }
}

/// Avatar redondo da linha: laranja suave quando ativo, cinza quando inativo.
class AvatarLista extends StatelessWidget {
  final IconData? icone;
  final String? letra;
  final bool ativo;

  const AvatarLista({super.key, this.icone, this.letra, this.ativo = true});

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? MdColors.primaryStrong : MdColors.textMuted;
    return CircleAvatar(
      radius: 22,
      backgroundColor: ativo ? MdColors.primarySoft : MdColors.background,
      child: icone != null
          ? Icon(icone, color: cor, size: 24)
          : Text(
              letra ?? '?',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(color: cor),
            ),
    );
  }
}

/// Linha secundária com ícone pequeno e texto em textMuted.
class LinhaInfo extends StatelessWidget {
  final IconData icone;
  final String texto;
  final int maxLines;

  const LinhaInfo({super.key, required this.icone, required this.texto, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icone, size: 16, color: MdColors.textMuted),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: MdColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Título de diálogo com ícone (laranja forte; vermelho em ações destrutivas).
class TituloDialogo extends StatelessWidget {
  final IconData icone;
  final String texto;
  final bool destrutivo;

  const TituloDialogo({
    super.key,
    required this.icone,
    required this.texto,
    this.destrutivo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, color: destrutivo ? MdColors.danger : MdColors.primaryStrong),
        const SizedBox(width: MdSpace.sm),
        Flexible(child: Text(texto)),
      ],
    );
  }
}

/// Botão de confirmação destrutiva (vermelho cheio).
class BotaoDestrutivo extends StatelessWidget {
  final String texto;
  final VoidCallback onPressed;

  const BotaoDestrutivo({super.key, required this.texto, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: MdColors.danger, foregroundColor: Colors.white),
      onPressed: onPressed,
      child: Text(texto),
    );
  }
}

/// Item do menu "⋮" dos cartões; [destrutivo] pinta de vermelho.
PopupMenuItem<String> itemMenu(String valor, IconData icone, String texto,
    {bool destrutivo = false}) {
  final cor = destrutivo ? MdColors.danger : null;
  return PopupMenuItem<String>(
    value: valor,
    child: Row(
      children: [
        Icon(icone, size: 20, color: cor ?? MdColors.textMuted),
        const SizedBox(width: MdSpace.md),
        Text(texto, style: cor == null ? null : TextStyle(color: cor)),
      ],
    ),
  );
}

/// Erro ao carregar a lista: faixa vermelha no topo.
class ErroDaLista extends StatelessWidget {
  final String texto;
  const ErroDaLista({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(MdSpace.lg),
        child: MdBanner(tipo: MdTipo.erro, texto: texto),
      ),
    );
  }
}

/// Status ativo/inativo como selo.
class SeloAtivo extends StatelessWidget {
  final bool ativo;
  const SeloAtivo({super.key, required this.ativo});

  @override
  Widget build(BuildContext context) => MdStatusChip(
        tipo: ativo ? MdTipo.sucesso : MdTipo.neutro,
        texto: ativo ? 'Ativo' : 'Inativo',
      );
}
