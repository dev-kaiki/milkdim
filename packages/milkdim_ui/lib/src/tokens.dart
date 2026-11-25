import 'package:flutter/painting.dart';

/// Nome da família Noto Sans empacotada no milkdim_ui, já com o prefixo de pacote.
const String mdFontFamily = 'packages/milkdim_ui/NotoSans';

/// Cores do novo visual (tabela do spec 2026-11-19-novo-visual-design.md).
abstract final class MdColors {
  /// Laranja da marca (fundos de botão, indicadores).
  static const Color primary = Color(0xFFE38A1D);

  /// Laranja de fundo para botões e áreas com texto branco (contraste ~3,6:1,
  /// o laranja da marca dá só 2,7:1 com branco).
  static const Color primaryFill = Color(0xFFC9700F);

  /// Laranja escuro para texto e ícone sobre fundo claro (contraste).
  static const Color primaryStrong = Color(0xFFA85C0C);

  /// Amarelo da marca: só em fundos e realces, nunca com texto claro.
  static const Color accent = Color(0xFFFFE066);

  /// Fundo das telas.
  static const Color background = Color(0xFFF7F5F2);

  /// Superfície de cartões, barras e diálogos.
  static const Color surface = Color(0xFFFFFFFF);

  /// Bordas e divisores.
  static const Color border = Color(0xFFE7E2DA);

  /// Texto principal.
  static const Color text = Color(0xFF1F1B16);

  /// Texto secundário.
  static const Color textMuted = Color(0xFF6B645B);
  /// Cinza das barras de saídas nos gráficos (mais claro que o texto).
  static const Color neutroGrafico = Color(0xFFA8A29A);

  /// Sucesso.
  static const Color success = Color(0xFF1E8E4E);

  /// Atenção.
  static const Color warning = Color(0xFFB7791F);

  /// Erro / ação destrutiva.
  static const Color danger = Color(0xFFC9372C);

  /// Informação.
  static const Color info = Color(0xFF2D6CDF);

  /// Laranja claro (primary a 14%) para indicadores de navegação e seleção.
  static const Color primarySoft = Color(0x24E38A1D);
}

/// Espaçamentos em múltiplos de 4.
abstract final class MdSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Raios de canto: campos e botões, cartões, diálogos.
abstract final class MdRadius {
  static const double field = 12;
  static const double card = 16;
  static const double dialog = 20;
}
