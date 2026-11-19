import 'package:flutter/material.dart';

import '../tokens.dart';

/// Tipo de mensagem/status: define cor e ícone de chips, banners e snackbars.
enum MdTipo { info, sucesso, atencao, erro, neutro }

/// Cores e ícone padrão de cada [MdTipo].
extension MdTipoVisual on MdTipo {
  /// Cor do tipo (ícones, bordas e base do fundo tingido).
  Color get cor => switch (this) {
        MdTipo.info => MdColors.info,
        MdTipo.sucesso => MdColors.success,
        MdTipo.atencao => MdColors.warning,
        MdTipo.erro => MdColors.danger,
        MdTipo.neutro => MdColors.textMuted,
      };

  /// Cor do texto sobre o fundo tingido: a cor do tipo escurecida para dar contraste.
  Color get corTexto => Color.lerp(cor, MdColors.text, 0.3)!;

  /// Fundo tingido (cerca de 12% da cor do tipo).
  Color get corFundo => cor.withValues(alpha: 0.12);

  /// Ícone padrão do tipo.
  IconData get icone => switch (this) {
        MdTipo.info => Icons.info_outline,
        MdTipo.sucesso => Icons.check_circle_outline,
        MdTipo.atencao => Icons.warning_amber_rounded,
        MdTipo.erro => Icons.error_outline,
        MdTipo.neutro => Icons.circle_outlined,
      };
}
