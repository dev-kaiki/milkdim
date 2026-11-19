import 'package:flutter/material.dart';

import '../tokens.dart';
import 'md_tipo.dart';

/// Cartão branco com borda de 1 px, raio 16 e toque opcional.
class MdCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const MdCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MdSpace.lg),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final conteudo = Padding(padding: padding, child: child);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? conteudo : InkWell(onTap: onTap, child: conteudo),
    );
  }
}

/// Selo de status em pílula: fundo tingido e texto forte da cor do [tipo].
class MdStatusChip extends StatelessWidget {
  final MdTipo tipo;
  final String texto;
  final IconData? icone;

  const MdStatusChip({super.key, required this.tipo, required this.texto, this.icone});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelMedium!.copyWith(
          color: tipo.corTexto,
          fontWeight: FontWeight.w700,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MdSpace.xs),
      decoration: ShapeDecoration(color: tipo.corFundo, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 16, color: tipo.cor),
            const SizedBox(width: MdSpace.xs),
          ],
          Flexible(child: Text(texto, style: estilo, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Faixa de aviso de largura total (ex.: "N pedidos aguardando envio") com ação opcional.
class MdBanner extends StatelessWidget {
  final MdTipo tipo;
  final String texto;
  final IconData? icone;
  final Widget? acao;

  const MdBanner({super.key, required this.tipo, required this.texto, this.icone, this.acao});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: tipo.corTexto,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg, vertical: MdSpace.md),
      decoration: BoxDecoration(
        color: tipo.corFundo,
        borderRadius: BorderRadius.circular(MdRadius.field),
        border: Border.all(color: tipo.cor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icone ?? tipo.icone, color: tipo.cor, size: 24),
          const SizedBox(width: MdSpace.md),
          Expanded(child: Text(texto, style: estilo)),
          if (acao != null) ...[const SizedBox(width: MdSpace.sm), acao!],
        ],
      ),
    );
  }
}

/// Estado vazio de lista: ícone em círculo, título, texto e ação opcionais.
class MdEmptyState extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? texto;
  final Widget? acao;

  const MdEmptyState({super.key, required this.icone, required this.titulo, this.texto, this.acao});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MdSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: MdColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icone, size: 36, color: MdColors.primaryStrong),
            ),
            const SizedBox(height: MdSpace.lg),
            Text(titulo, style: tt.titleMedium, textAlign: TextAlign.center),
            if (texto != null) ...[
              const SizedBox(height: MdSpace.sm),
              Text(
                texto!,
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (acao != null) ...[const SizedBox(height: MdSpace.xl), acao!],
          ],
        ),
      ),
    );
  }
}

/// Título de seção com widget opcional à direita (ex.: "Ver todos").
class MdSectionHeader extends StatelessWidget {
  final String titulo;
  final Widget? trailing;

  const MdSectionHeader({super.key, required this.titulo, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: MdSpace.sm, bottom: MdSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Ação grande do início do vendedor (altura mínima 88); [destaque] = laranja cheio.
class MdActionTile extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;
  final VoidCallback? onTap;
  final bool destaque;

  const MdActionTile({
    super.key,
    required this.icone,
    required this.titulo,
    this.subtitulo,
    required this.onTap,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final frente = destaque ? Colors.white : MdColors.text;
    final fundoIcone = destaque ? Colors.white.withValues(alpha: 0.22) : MdColors.primarySoft;
    final corIcone = destaque ? Colors.white : MdColors.primaryStrong;
    final ativo = onTap != null;

    final tile = Material(
      color: destaque ? MdColors.primary : MdColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MdRadius.card),
        side: destaque ? BorderSide.none : const BorderSide(color: MdColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MdSpace.lg, vertical: MdSpace.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: fundoIcone, shape: BoxShape.circle),
                  child: Icon(icone, size: 28, color: corIcone),
                ),
                const SizedBox(width: MdSpace.lg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: tt.titleMedium!.copyWith(color: frente, fontSize: 18)),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          style: tt.bodyMedium!.copyWith(
                            color: destaque ? Colors.white : MdColors.textMuted,
                            fontWeight: destaque ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: destaque ? Colors.white : MdColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: ativo,
      child: ativo ? tile : Opacity(opacity: 0.55, child: tile),
    );
  }
}

/// Mostra um snackbar flutuante: sucesso em verde, erro em vermelho, demais em escuro.
void showMdSnack(BuildContext context, String texto, {MdTipo tipo = MdTipo.neutro}) {
  final fundo = switch (tipo) {
    MdTipo.sucesso => MdColors.success,
    MdTipo.erro => MdColors.danger,
    _ => MdColors.text,
  };
  final estilo = Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      );
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: fundo,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            if (tipo != MdTipo.neutro) ...[
              Icon(tipo.icone, color: Colors.white, size: 20),
              const SizedBox(width: MdSpace.md),
            ],
            Expanded(child: Text(texto, style: estilo)),
          ],
        ),
      ),
    );
}

/// Campo de busca com lupa e botão de limpar quando há texto.
class MdSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const MdSearchField({super.key, this.controller, this.hint = 'Buscar', this.onChanged});

  @override
  State<MdSearchField> createState() => _MdSearchFieldState();
}

class _MdSearchFieldState extends State<MdSearchField> {
  TextEditingController? _interno;

  TextEditingController get _controller =>
      widget.controller ?? (_interno ??= TextEditingController());

  @override
  void dispose() {
    _interno?.dispose();
    super.dispose();
  }

  void _limpar() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, valor, _) => TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: valor.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Limpar busca',
                  onPressed: _limpar,
                ),
        ),
      ),
    );
  }
}

/// Centraliza e limita a largura do conteúdo em telas largas (padrão 1100 px).
class MdContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MdContentWidth({super.key, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
