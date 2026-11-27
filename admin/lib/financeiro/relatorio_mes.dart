// lib/financeiro/relatorio_mes.dart
//
// Relatório mensal do Financeiro: o modelo (tudo já em texto) e o PDF.
// Não faz conta nova: usa o resumo, a comparação e as saídas que a tela
// já carregou, com os mesmos textos de variação e margem.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../etiqueta/etiqueta_pdf.dart' show carregarFonte;
import '../models/pedido.dart';
import 'abas/aba_resumo.dart' show textoVariacao;
import 'modelos_financeiro.dart';
import 'painel_financeiro.dart';
import 'resumo_financeiro.dart';

/// Nomes dos meses em português, com inicial maiúscula (índice = mês - 1).
const List<String> nomesMeses = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

const String _semDado = '—';
const String _listaVazia = 'Nenhum lançamento.';
const String _textoAviso = 'Até 23/11/2026, a data é a do pedido.';

/// Uma linha do resumo: rótulo, valor e, quando há, a variação do mês.
typedef LinhaResumo = ({String rotulo, String valor, String? variacao});

/// Relatório pronto para o PDF. Cada tabela é uma lista de linhas de células.
class RelatorioMes {
  const RelatorioMes({
    required this.titulo,
    required this.geradoEm,
    required this.resumo,
    required this.porVendedor,
    required this.porProduto,
    required this.porCategoria,
    required this.saidas,
    required this.entregues,
    this.aReceber,
    this.aviso,
  });

  final String titulo;

  /// "Gerado em dd/MM/aaaa HH:mm".
  final String geradoEm;
  final List<LinhaResumo> resumo;

  /// [vendedor, pedidos, valor].
  final List<List<String>> porVendedor;

  /// [produto, quantidade, valor].
  final List<List<String>> porProduto;

  /// [categoria, lançamentos, valor].
  final List<List<String>> porCategoria;

  /// [data, categoria, descrição, valor], em ordem de data.
  final List<List<String>> saidas;

  /// [data, número, cliente, valor], em ordem de data.
  final List<List<String>> entregues;

  /// "N pedidos · R$ x"; nulo fora do mês atual.
  final String? aReceber;

  /// Nota do período antigo; nulo depois de novembro de 2026.
  final String? aviso;
}

String _dois(int n) => n.toString().padLeft(2, '0');

String _data(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

String _plural(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

List<List<String>> _linhas(List<LinhaValor> l) => [
      for (final x in l) [x.rotulo, '${x.quantidade}', fmtCentavos(x.centavos)],
    ];

String _cliente(Pedido p) {
  for (final s in [p.clienteNomeFantasia, p.clienteNome]) {
    final t = (s ?? '').trim();
    if (t.isNotEmpty) return t;
  }
  return _semDado;
}

String? _variacao(Variacao? v) => v == null ? null : textoVariacao(v);

RelatorioMes montarRelatorio({
  required int ano,
  required int mes,
  required DateTime geradoEm,
  required bool mesAtual,
  required ResumoMes resumo,
  ComparacaoMes? comparacao,
  required List<Saida> saidas,
  required Map<int, String> nomesCategorias,
  required List<Pedido> entregues,
}) {
  final margem = pctDe(resumo.resultadoCentavos, resumo.vendasCentavos);

  final saidasOrd = [...saidas]..sort((a, b) => a.data.compareTo(b.data));
  // Sem data (não deveria ocorrer) vai para o fim.
  final entreguesOrd = [...entregues]..sort((a, b) {
      final x = a.finalizadoEm, y = b.finalizadoEm;
      if (x == null || y == null) {
        return x == null && y == null ? 0 : (x == null ? 1 : -1);
      }
      return x.compareTo(y);
    });

  return RelatorioMes(
    titulo:
        'MilkDim · Relatório de ${nomesMeses[mes - 1].toLowerCase()} de $ano',
    geradoEm: 'Gerado em ${_data(geradoEm)} '
        '${_dois(geradoEm.hour)}:${_dois(geradoEm.minute)}',
    resumo: [
      (
        rotulo: 'Vendas',
        valor: fmtCentavos(resumo.vendasCentavos),
        variacao: _variacao(comparacao?.vendas),
      ),
      (
        rotulo: 'Pedidos entregues',
        valor: '${resumo.pedidos}',
        variacao: null,
      ),
      (
        rotulo: 'Saídas',
        valor: fmtCentavos(resumo.saidasCentavos),
        variacao: _variacao(comparacao?.saidas),
      ),
      (
        rotulo: 'Resultado',
        valor: fmtCentavos(resumo.resultadoCentavos),
        variacao: _variacao(comparacao?.resultado),
      ),
      (
        rotulo: 'Margem',
        valor: margem == null ? _semDado : '$margem%',
        variacao: null,
      ),
    ],
    porVendedor: _linhas(resumo.porVendedor),
    porProduto: _linhas(resumo.porProduto),
    porCategoria: _linhas(resumo.porCategoria),
    saidas: [
      for (final s in saidasOrd)
        [
          _data(s.data),
          nomesCategorias[s.categoriaId] ?? 'Sem categoria',
          s.descricao.trim().isEmpty ? _semDado : s.descricao.trim(),
          fmtCentavos(s.valorCentavos),
        ],
    ],
    entregues: [
      for (final p in entreguesOrd)
        [
          p.finalizadoEm == null ? _semDado : _data(p.finalizadoEm!),
          (p.numero ?? '').trim().isEmpty ? '${p.id}' : p.numero!.trim(),
          _cliente(p),
          fmtCentavos(centavos(p.total)),
        ],
    ],
    aReceber: mesAtual
        ? '${_plural(resumo.aReceberPedidos, 'pedido', 'pedidos')} · '
            '${fmtCentavos(resumo.aReceberCentavos)}'
        : null,
    aviso: (ano < 2026 || (ano == 2026 && mes <= 11)) ? _textoAviso : null,
  );
}

String nomeArquivoRelatorio(int ano, int mes) =>
    'Relatorio_MilkDim_$ano-${_dois(mes)}.pdf';

/// PDF A4 do relatório; quebra de página automática nas tabelas longas.
Future<Uint8List> pdfDoRelatorio(RelatorioMes r) async {
  final negrito =
      await carregarFonte('NotoSans-Bold.ttf', pw.Font.helveticaBold());
  final normal =
      await carregarFonte('NotoSans-Regular.ttf', pw.Font.helvetica());
  final doc = pw.Document(title: r.titulo);

  const cinza = PdfColors.grey700;
  final estilo = pw.TextStyle(font: normal, fontSize: 10);
  final estiloNegrito = pw.TextStyle(font: negrito, fontSize: 10);

  pw.Widget secao(String nome) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Text(nome, style: pw.TextStyle(font: negrito, fontSize: 13)),
      );

  // As últimas [colunasDireita] colunas (valores) ficam alinhadas à direita.
  pw.Widget grade(List<String> cab, List<List<String>> linhas,
      {int colunasDireita = 1}) {
    final n = cab.length;
    final direita = {
      for (var i = n - colunasDireita; i < n; i++) i: pw.Alignment.centerRight,
    };
    return pw.TableHelper.fromTextArray(
      headers: cab,
      data: linhas,
      headerStyle: estiloNegrito,
      cellStyle: estilo,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellAlignments: direita,
      headerAlignments: direita,
    );
  }

  pw.Widget tabela(List<String> cab, List<List<String>> linhas,
          {int colunasDireita = 1}) =>
      linhas.isEmpty
          ? pw.Text(_listaVazia, style: estilo.copyWith(color: cinza))
          : grade(cab, linhas, colunasDireita: colunasDireita);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Página ${c.pageNumber} de ${c.pagesCount}',
          style: estilo.copyWith(fontSize: 8, color: cinza)),
    ),
    build: (c) => [
      pw.Text(r.titulo, style: pw.TextStyle(font: negrito, fontSize: 18)),
      pw.SizedBox(height: 2),
      pw.Text(r.geradoEm, style: estilo.copyWith(color: cinza)),
      if (r.aviso != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(r.aviso!, style: estilo.copyWith(color: cinza)),
      ],
      secao('Resumo'),
      grade(
        const ['', 'Valor', 'Variação'],
        [
          for (final l in r.resumo) [l.rotulo, l.valor, l.variacao ?? ''],
        ],
        colunasDireita: 2,
      ),
      secao('Vendas por vendedor'),
      tabela(const ['Vendedor', 'Pedidos', 'Valor'], r.porVendedor,
          colunasDireita: 2),
      secao('Vendas por produto'),
      tabela(const ['Produto', 'Quantidade', 'Valor'], r.porProduto,
          colunasDireita: 2),
      secao('Saídas por categoria'),
      tabela(const ['Categoria', 'Lançamentos', 'Valor'], r.porCategoria,
          colunasDireita: 2),
      secao('Saídas do mês'),
      tabela(const ['Data', 'Categoria', 'Descrição', 'Valor'], r.saidas),
      secao('Pedidos entregues'),
      tabela(const ['Data', 'Pedido', 'Cliente', 'Valor'], r.entregues),
      if (r.aReceber != null) ...[
        secao('A receber'),
        pw.Text(r.aReceber!, style: estilo),
      ],
    ],
  ));
  return doc.save();
}
