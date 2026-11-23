// Regras puras do fluxo do pedido (sem Flutter nem banco), usadas pelas telas.
import 'dart:convert';
import 'dart:io' show File;

import 'db.dart' show buscarUltimoNumeroPedido, jaChegouAoServidor, kErroNumeroEmUso, numeroUsadoNoAparelho;
import 'supabase_helper.dart' show ResultadoGravacao, kPrazoConsultaNumero, numeroLivreNoServidor;

/// Texto único de número em uso (tela de pedido novo, edição e selo da lista).
const String kMsgNumeroEmUso = 'Número já usado; troque o número';

bool _verdadeiro(Object? v) => v == true || '$v' == '1';

/// O número só muda enquanto o pedido não chegou ao servidor, ou quando o
/// servidor recusou o número por já ser de outro pedido.
bool numeroEditavel(Map<String, dynamic> p) =>
    !jaChegouAoServidor(p) || p['erro_envio']?.toString() == kErroNumeroEmUso;

/// O que o botão de remover do pedido faz.
enum AcaoRemover { cancelar, apagarDoAparelho, nenhuma }

/// Pronto para entrega: a fábrica concluiu a produção (só o Controle grava).
bool estaPronto(Map p) => _status(p) == 'pronto';

/// Aba "Em aberto" de Meus pedidos: `salvo` e `pronto`.
bool estaEmAberto(Map p) {
  final st = _status(p);
  return st == 'salvo' || st == 'pronto';
}

String _status(Map p) => (p['status'] ?? '').toString().trim().toLowerCase();

/// `pronto` conta como `salvo` (em aberto): cancelar, nunca apagar.
AcaoRemover acaoRemover(Map<String, dynamic> p) {
  if (!estaEmAberto(p)) return AcaoRemover.nenhuma;
  if (_verdadeiro(p['so_local'])) return AcaoRemover.apagarDoAparelho;
  if (jaChegouAoServidor(p) || _verdadeiro(p['pendente_envio'])) {
    return AcaoRemover.cancelar;
  }
  return AcaoRemover.nenhuma;
}

/// Mensagem para o vendedor depois de gravar, ou null quando não há nada novo
/// a dizer (o `enviado` de um finalizado mantém o comportamento de sempre).
String? mensagemGravacao(ResultadoGravacao r, String status) {
  switch (r) {
    case ResultadoGravacao.enviado:
      // `pronto` só volta da tela quando nada mudou: o pedido já estava na
      // produção (e pronto), então não é "enviado para produção".
      return switch (status) {
        'salvo' => 'Pedido enviado para produção.',
        'pronto' => 'Pedido salvo.',
        _ => null,
      };
    case ResultadoGravacao.pendente:
      return 'Pedido salvo. Será enviado quando houver internet.';
    case ResultadoGravacao.fechadoNoControle:
      return 'Este pedido já foi finalizado no Controle.';
    case ResultadoGravacao.canceladoNoControle:
      return 'Este pedido foi cancelado no Controle.';
    case ResultadoGravacao.numeroEmUso:
      return kMsgNumeroEmUso;
    case ResultadoGravacao.rascunho:
      return null;
  }
}

/// O servidor recusou o número deste pedido (de qualquer status): a lista
/// oferece "Trocar número".
bool podeTrocarNumero(Map<String, dynamic> p) =>
    p['erro_envio']?.toString() == kErroNumeroEmUso;

/// Resultados que o vendedor precisa notar (não são sucesso).
bool gravacaoEhAviso(ResultadoGravacao r) =>
    r == ResultadoGravacao.numeroEmUso ||
    r == ResultadoGravacao.fechadoNoControle ||
    r == ResultadoGravacao.canceladoNoControle;

/// Primeiro número a partir de [inicio] para o qual [livre] devolve true, em
/// no máximo [tentativas] tentativas; null se todos estiverem ocupados.
Future<String?> proximoNumeroLivre(
  int inicio,
  Future<bool> Function(String numero) livre, {
  int tentativas = 20,
}) async {
  for (var i = 0; i < tentativas; i++) {
    final n = (inicio + i).toString();
    if (await livre(n)) return n;
  }
  return null;
}

/// Número livre no aparelho e no servidor (sem internet, ou sem resposta do
/// servidor em [prazo], o servidor não bloqueia).
Future<bool> numeroLivreParaVendedor(String numero, String vendedorCodigo,
    {Duration prazo = kPrazoConsultaNumero}) async {
  if (numero.isEmpty) return true;
  if (await numeroUsadoNoAparelho(numero, vendedorCodigo)) return false;
  return numeroLivreNoServidor(numero, vendedorCodigo, prazo: prazo);
}

/// Próximo número livre do vendedor: último local + 1, até 20 tentativas.
/// O servidor tem [prazo] no total (não por tentativa): esgotado, as
/// tentativas que faltam olham só o aparelho (regra do offline).
Future<String?> proximoNumeroLivreDoVendedor(String vendedorCodigo,
    {Duration prazo = kPrazoConsultaNumero}) async {
  final ultimo = (await buscarUltimoNumeroPedido()) ?? 0;
  final relogio = Stopwatch()..start();
  return proximoNumeroLivre(ultimo + 1, (n) async {
    if (await numeroUsadoNoAparelho(n, vendedorCodigo)) return false;
    final resta = prazo - relogio.elapsed;
    if (resta <= Duration.zero) return true;
    return numeroLivreNoServidor(n, vendedorCodigo, prazo: resta);
  });
}

// ---------------------- Assinatura do pedido ----------------------

/// Aviso da tela de assinatura: pedido nunca assinado (ou rascunho).
const String kAvisoAssinarPedido = 'O cliente precisa assinar o pedido.';

/// Aviso da tela de assinatura: pedido assinado cujos itens ou cliente mudaram.
const String kAvisoAssinarPedidoDeNovo =
    'O cliente precisa assinar o pedido de novo, porque os itens mudaram.';

double _numero(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.trim().replaceAll(',', '.')) ?? 0.0;
}

int? _inteiro(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());

/// Itens comparáveis: nome, quantidade e preço de cada um, em ordem fixa
/// (a ordem da lista e o subtotal não contam). Quantidade e preço contam
/// **exatos**, como números (2 e 2.0 são iguais; 18.9 e 18.900000000000002
/// não): o servidor compara o jsonb, então só o subtotal pode ter ruído.
/// `produtos` pode ser a lista ou o texto JSON do SQLite. null se não der
/// para ler.
List<String>? _itensComparaveis(Object? produtos) {
  Object? lista = produtos;
  if (lista is String) {
    try {
      lista = jsonDecode(lista);
    } catch (_) {
      return null;
    }
  }
  if (lista == null) return const [];
  if (lista is! List) return null;
  final out = <String>[];
  for (final it in lista) {
    if (it is! Map) return null;
    // double.toString() é a forma mais curta que volta ao mesmo double:
    // textos iguais <=> números iguais.
    out.add('${(it['nome'] ?? '').toString().trim()}'
        '|${_numero(it['quantidade'])}'
        '|${_numero(it['preco'])}');
  }
  out.sort();
  return out;
}

/// Os itens das duas versões são os mesmos (nome, quantidade e preço)?
/// Ilegível de qualquer lado: não.
bool mesmosItens(Object? antes, Object? depois) {
  final a = _itensComparaveis(antes);
  final b = _itensComparaveis(depois);
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Nome do cliente para comparar: sem espaços nas pontas, e null vale ''.
String nomeClienteComparavel(Object? v) => (v ?? '').toString().trim();

/// Mudaram os itens (nome, quantidade, preço), o `cliente_id` ou o
/// `cliente_nome`? É o que tira um pedido de `pronto` no servidor.
/// O nome é comparado sem espaços nas pontas e com null igual a '': salvar de
/// novo sem mexer não pede assinatura. O servidor compara o valor cru, por
/// isso `pedidoDaTela` manda o nome guardado quando só mudam espaços.
bool itensOuClienteMudaram(Map antes, Map depois) =>
    !mesmosItens(antes['produtos'], depois['produtos']) ||
    _inteiro(antes['cliente_id']) != _inteiro(depois['cliente_id']) ||
    nomeClienteComparavel(antes['cliente_nome']) !=
        nomeClienteComparavel(depois['cliente_nome']);

/// Os bytes da assinatura existem (lista não vazia, ou texto hex/base64 com
/// conteúdo além do prefixo `0x`/`\x`)?
bool _temBytes(Object? v) {
  if (v is List) return v.isNotEmpty;
  if (v == null) return false;
  final t = '$v'.trim();
  return t.isNotEmpty && t != '0x' && t != r'\x';
}

/// O arquivo existe no aparelho (aceita `file://`).
bool arquivoExisteNoAparelho(String caminho) {
  try {
    final p = caminho.startsWith('file://') ? Uri.parse(caminho).toFilePath() : caminho;
    return File(p).existsSync();
  } catch (_) {
    return false;
  }
}

/// O pedido tem a assinatura do pedido: os bytes (`assinatura_pedido`) ou o
/// arquivo de `assinatura_pedido_path` **existindo** no aparelho. Só o
/// caminho, sem o arquivo, não conta.
bool temAssinaturaDoPedido(Map p,
    {bool Function(String caminho) arquivoExiste = arquivoExisteNoAparelho}) {
  if (_temBytes(p['assinatura_pedido'])) return true;
  final caminho = (p['assinatura_pedido_path'] ?? '').toString().trim();
  return caminho.isNotEmpty && arquivoExiste(caminho);
}

/// Salvar [editado] pede a assinatura do pedido de novo?
/// - [original] não tem assinatura do pedido ([temAssinaturaDoPedido]);
/// - mudaram os itens ou o cliente ([itensOuClienteMudaram]).
/// Vale igual para o rascunho do aparelho (`so_local = 1`): o rascunho só
/// guarda a assinatura do pedido quando ela cobre os itens e o cliente dele
/// ("Salvar rascunho" apaga a que não cobre), então a linha guardada é o que
/// o cliente assinou.
bool precisaAssinaturaDoPedido({
  required Map original,
  required Map editado,
  bool Function(String caminho) arquivoExiste = arquivoExisteNoAparelho,
}) =>
    !temAssinaturaDoPedido(original, arquivoExiste: arquivoExiste) ||
    itensOuClienteMudaram(original, editado);

/// O aviso da tela de assinatura ao salvar [editado], ou null quando não
/// precisa de assinatura nova ([precisaAssinaturaDoPedido]).
/// Pedido (ou rascunho) já assinado: [kAvisoAssinarPedidoDeNovo]; pedido sem
/// assinatura: [kAvisoAssinarPedido].
String? avisoAssinaturaDoPedido({
  required Map original,
  required Map editado,
  bool Function(String caminho) arquivoExiste = arquivoExisteNoAparelho,
}) {
  if (!precisaAssinaturaDoPedido(
      original: original, editado: editado, arquivoExiste: arquivoExiste)) {
    return null;
  }
  final jaAssinado = temAssinaturaDoPedido(original, arquivoExiste: arquivoExiste);
  return jaAssinado ? kAvisoAssinarPedidoDeNovo : kAvisoAssinarPedido;
}

/// Rascunho só do aparelho (`so_local = 1`): nunca foi enviado.
bool ehRascunhoDoAparelho(Map p) => _verdadeiro(p['so_local']);
