import 'package:flutter/material.dart';

import '../tokens.dart';

/// Logo arredondado + "MilkDim", para a barra superior e telas de entrada.
class MdLogoTitle extends StatelessWidget {
  /// Lado do logo em pixels lógicos.
  final double logoSize;

  /// Imagem do logo; por padrão o `assets/logo.jpg` empacotado no milkdim_ui.
  final ImageProvider? logo;

  /// Texto ao lado do logo.
  final String texto;

  const MdLogoTitle({super.key, this.logoSize = 32, this.logo, this.texto = 'MilkDim'});

  /// Logo padrão empacotado no milkdim_ui.
  static const ImageProvider logoPadrao = AssetImage('assets/logo.jpg', package: 'milkdim_ui');

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.titleLarge!.copyWith(
          fontWeight: FontWeight.w700,
          color: MdColors.text,
          fontSize: (logoSize * 0.62).clamp(18, 34).toDouble(),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(logoSize * 0.25),
          child: Image(
            image: logo ?? logoPadrao,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            semanticLabel: 'Logo MilkDim',
            errorBuilder: (_, __, ___) => Container(
              width: logoSize,
              height: logoSize,
              color: MdColors.accent,
              alignment: Alignment.center,
              child: Text(
                'M',
                style: estilo.copyWith(color: MdColors.primaryStrong, fontSize: logoSize * 0.5),
              ),
            ),
          ),
        ),
        SizedBox(width: logoSize >= 48 ? MdSpace.md : MdSpace.sm),
        Text(texto, style: estilo),
      ],
    );
  }
}
