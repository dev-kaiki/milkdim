import 'package:intl/intl.dart';

final NumberFormat _reais = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

/// Valor em reais para a tela: "R$ 1.234,56". O PDF tem formatação própria.
String formatarReais(num valor) => _reais.format(valor);
