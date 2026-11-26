import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:milkdim_ui/milkdim_ui.dart';

import '../models/pedido.dart';
import '../models/produto.dart';
import '../services/caixas_service.dart';
import '../services/supabase_service.dart';
import '../widgets/lista_adaptavel.dart';
import 'etiqueta_pdf.dart';
import 'tamanho_etiqueta.dart';
import 'tela_volumes.dart';
import 'volumes.dart';

/// Envia o PDF para a impressora. Devolve false se o diálogo do sistema foi
/// cancelado (nada saiu).
typedef EnviarParaImpressora = Future<bool> Function(Uint8List pdf, TamanhoEtiqueta t);

Future<bool> _enviarPadrao(Uint8List pdf, TamanhoEtiqueta t) {
  final formato = PdfPageFormat(
    t.larguraMm * PdfPageFormat.mm,
    t.alturaMm * PdfPageFormat.mm,
  );
  return Printing.layoutPdf(
    name: 'Etiqueta',
    format: formato,
    usePrinterSettings: true,
    onLayout: (_) async => pdf,
  );
}

/// Dados da etiqueta a partir do pedido (nome fantasia, se houver, senão o nome).
/// O vendedor sai pelo nome; sem nome no pedido, pelo código. Sem telefone,
/// vai o WhatsApp.
EtiquetaDados etiquetaDoPedido(Pedido p) {
  final fantasia = (p.clienteNomeFantasia ?? '').trim();
  final nome = (p.clienteNome ?? '').trim();
  final nomeVendedor = (p.vendedorNome ?? '').trim();
  final telefone = (p.clienteTelefone ?? '').trim();
  return EtiquetaDados(
    numero: int.tryParse((p.numero ?? '').trim()) ?? p.id,
    clienteTitulo: fantasia.isNotEmpty ? fantasia : nome,
    cidade: (p.clienteCidade ?? '').trim(),
    vendedor: nomeVendedor.isNotEmpty ? nomeVendedor : (p.vendedorCodigo ?? '').trim(),
    itens: [for (final i in p.itens) (nome: i.nome.trim(), quantidade: i.quantidade)],
    prontoEm: p.prontoEm,
    codigoQr: p.codigoQr ?? '',
    endereco: (p.clienteEndereco ?? '').trim(),
    cep: (p.clienteCep ?? '').trim(),
    telefone: telefone.isNotEmpty ? telefone : (p.clienteWhatsapp ?? '').trim(),
  );
}

enum _Resposta { sim, denovo, cancelar }

/// Gera a etiqueta, envia para a impressora e pergunta se saiu certa. Só o
/// "Sim" chama [marcar], com o `alterado_em` (texto bruto) do pedido de onde
/// a etiqueta saiu: o servidor recusa se o pedido mudou depois. Devolve true
/// se marcou. Com [marcarAoConfirmar] falso (reimpressão de pedido já
/// entregue) o "Sim" só fecha a pergunta e [marcar] nunca é chamado; o
/// retorno é false.
Future<bool> imprimirEtiquetaComConfirmacao(
  BuildContext context,
  Pedido p, {
  required Future<void> Function(int id, String? alteradoEmBruto) marcar,
  EnviarParaImpressora? enviar,
  bool marcarAoConfirmar = true,
}) async {
  TamanhoEtiqueta tamanho;
  try {
    tamanho = await lerTamanhoEtiqueta();
  } catch (_) {
    tamanho = TamanhoEtiqueta.m100x100;
  }
  final envio = enviar ?? _enviarPadrao;
  while (true) {
    final pdf = await gerarEtiquetaPdf(etiquetaDoPedido(p), tamanho);
    final saiu = await envio(pdf, tamanho);
    if (!saiu) return false;
    if (!context.mounted) return false;
    final r = await showDialog<_Resposta>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const TituloDialogo(
          icone: Icons.print_outlined,
          texto: 'A etiqueta saiu certa?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.cancelar),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.denovo),
            child: const Text('Imprimir de novo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.sim),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    switch (r) {
      case _Resposta.sim:
        if (!marcarAoConfirmar) return false;
        await marcar(p.id, p.alteradoEmBruto);
        return true;
      case _Resposta.denovo:
        continue;
      case _Resposta.cancelar:
      case null:
        return false;
    }
  }
}

/// Fonte de caixas quando o serviço real nem pôde ser criado: toda leitura
/// falha e o fluxo cai na etiqueta única.
class _FonteIndisponivel implements FonteCaixas {
  static Future<T> _falha<T>() =>
      Future<T>.error(RepoFailure('Caixas indisponíveis'));

  @override
  Future<List<TipoCaixa>> tiposCaixa() => _falha();
  @override
  Future<void> criarTipo(String nome, int capacidade, bool mistura) => _falha();
  @override
  Future<void> alterarTipo(TipoCaixa t) => _falha();
  @override
  Future<VolumesPedido?> volumesSalvos(int pedidoId) => _falha();
  @override
  Future<void> salvarVolumes(int pedidoId, VolumesPedido v) => _falha();
  @override
  Future<void> definirTipoDoProduto(int produtoId, int? tipoId) => _falha();
}

FonteCaixas _fonteCaixasPadrao() {
  try {
    return CaixasService();
  } catch (_) {
    return _FonteIndisponivel();
  }
}

Future<List<Produto>> _produtosPadrao() => SupabaseService().buscarProdutos();

const _avisoSemCaixas = 'Caixas indisponíveis; imprimindo etiqueta única.';

/// Ponto de entrada das telas: carrega os produtos e chama
/// [imprimirEtiquetasComVolumes]. Se os produtos não carregarem, cai na
/// etiqueta única, como quando os tipos de caixa estão indisponíveis.
Future<bool> imprimirEtiquetasDoPedido(
  BuildContext context,
  Pedido p, {
  FonteCaixas? fonte,
  Future<List<Produto>> Function()? carregarProdutos,
  required Future<void> Function(int id, String? alteradoEmBruto) marcar,
  EnviarParaImpressora? enviar,
}) async {
  if (p.status == 'cancelado') return false;
  List<Produto> produtos;
  try {
    produtos = await (carregarProdutos ?? _produtosPadrao)();
  } catch (_) {
    if (!context.mounted) return false;
    showMdSnack(context, _avisoSemCaixas);
    return imprimirEtiquetaComConfirmacao(context, p,
        marcar: marcar,
        enviar: enviar,
        marcarAoConfirmar: p.status != 'finalizado');
  }
  if (!context.mounted) return false;
  return imprimirEtiquetasComVolumes(
    context,
    p,
    fonte: fonte ?? _fonteCaixasPadrao(),
    produtos: produtos,
    marcar: marcar,
    enviar: enviar,
  );
}

/// Fluxo por caixa: monta/confere os volumes na tela, salva (pedido não
/// finalizado), imprime uma etiqueta por volume num único PDF e pergunta se
/// saíram certas. Só o "Sim" chama [marcar]. Devolve true se marcou.
Future<bool> imprimirEtiquetasComVolumes(
  BuildContext context,
  Pedido p, {
  required FonteCaixas fonte,
  required List<Produto> produtos,
  required Future<void> Function(int id, String? alteradoEmBruto) marcar,
  EnviarParaImpressora? enviar,
}) async {
  if (p.status == 'cancelado') return false;
  final finalizado = p.status == 'finalizado';

  List<TipoCaixa> tipos;
  VolumesPedido? salvos;
  try {
    tipos = await fonte.tiposCaixa();
    salvos = await fonte.volumesSalvos(p.id);
  } catch (_) {
    if (!context.mounted) return false;
    showMdSnack(context, _avisoSemCaixas);
    return imprimirEtiquetaComConfirmacao(context, p,
        marcar: marcar, enviar: enviar, marcarAoConfirmar: !finalizado);
  }
  if (!context.mounted) return false;

  final salvosValem = salvos != null && volumesValem(p.itens, salvos);
  // Pedido finalizado só reimprime o que foi salvo; sem isso, etiqueta única.
  if (finalizado && !salvosValem) {
    return imprimirEtiquetaComConfirmacao(context, p,
        marcar: marcar, enviar: enviar, marcarAoConfirmar: false);
  }

  final porProduto = tiposPorNomeDeProduto(produtos, tipos);
  final sugestao = sugerirVolumes(p.itens, porProduto);
  final inicial = salvosValem ? salvos : sugestao;
  final avisos = <String>[
    if (salvos != null && !salvosValem)
      'O pedido mudou depois que as caixas foram montadas.',
    // Item sem produto cadastrado vai para os avulsos; a tela avisa.
    if (!salvosValem) ...() {
      final vistos = <String>{};
      final nomes = <String>[];
      for (final i in p.itens) {
        final k = chaveNome(i.nome);
        if (!porProduto.containsKey(k) && vistos.add(k)) nomes.add(i.nome.trim());
      }
      return [
        if (nomes.isNotEmpty)
          'Sem cadastro: ${nomes.join(', ')} (foi para os avulsos).'
      ];
    }(),
  ];

  final volumes = await mostrarTelaVolumes(
    context,
    pedido: p,
    inicial: inicial,
    tiposPorNome: {for (final t in tipos) t.nome: t},
    avisos: avisos,
    somenteLeitura: finalizado,
    sugestao: sugestao,
  );
  if (volumes == null || !context.mounted) return false;

  if (!finalizado) {
    try {
      await fonte.salvarVolumes(p.id, volumes);
    } catch (e) {
      if (context.mounted) {
        final msg = e is RepoFailure ? e.message : 'Erro ao salvar as caixas.';
        showMdSnack(context, msg, tipo: MdTipo.erro);
      }
      return false;
    }
    if (!context.mounted) return false;
  }

  TamanhoEtiqueta tamanho;
  try {
    tamanho = await lerTamanhoEtiqueta();
  } catch (_) {
    tamanho = TamanhoEtiqueta.m100x100;
  }
  final envio = enviar ?? _enviarPadrao;
  final todas = etiquetasDosVolumes(etiquetaDoPedido(p), volumes);
  var lista = todas;
  var enviarAgora = true;
  while (true) {
    if (enviarAgora) {
      final pdf = await gerarEtiquetasPdf(lista, tamanho);
      final saiu = await envio(pdf, tamanho);
      if (!saiu || !context.mounted) return false;
    }
    if (!context.mounted) return false;
    final r = await showDialog<_Resposta>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const TituloDialogo(
          icone: Icons.print_outlined,
          texto: 'As etiquetas saíram certas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.cancelar),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.denovo),
            child: const Text('Imprimir de novo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.sim),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    switch (r) {
      case _Resposta.sim:
        // Pedido entregue só reimprime: nada a marcar.
        if (finalizado) return false;
        await marcar(p.id, p.alteradoEmBruto);
        return true;
      case _Resposta.denovo:
        if (!context.mounted) return false;
        // Com um volume só (ou pedido solto) não há o que escolher.
        final i = todas.length <= 1 ? -1 : await _escolherVolume(context, volumes);
        if (!context.mounted) return false;
        if (i == null) {
          enviarAgora = false; // desistiu da escolha: pergunta de novo
        } else {
          enviarAgora = true;
          lista = i < 0 ? todas : [todas[i]];
        }
        continue;
      case _Resposta.cancelar:
      case null:
        return false;
    }
  }
}

/// Escolhe o que reimprimir: -1 = todas, i = volume i (0-based), null = nada.
Future<int?> _escolherVolume(BuildContext context, VolumesPedido v) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Imprimir de novo'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(-1),
          child: const Text('Todas'),
        ),
        for (var i = 0; i < v.volumes.length; i++)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(i),
            child: Text(rotuloVolume(v, i)),
          ),
      ],
    ),
  );
}
