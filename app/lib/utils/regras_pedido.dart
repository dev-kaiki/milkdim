// Regras puras do fluxo do pedido (sem Flutter nem banco), usadas pelas telas.
import 'dart:convert';

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
      return status == 'salvo' ? 'Pedido enviado para produção.' : null;
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

double _numero(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.trim().replaceAll(',', '.')) ?? 0.0;
}

int? _inteiro(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());

/// Itens comparáveis: nome, quantidade e preço de cada um, em ordem fixa
/// (a ordem da lista e o subtotal não contam). `produtos` pode ser a lista ou
/// o texto JSON do SQLite. null se não der para ler.
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
    out.add('${(it['nome'] ?? '').toString().trim()}'
        '|${_numero(it['quantidade']).toStringAsFixed(3)}'
        '|${_numero(it['preco']).toStringAsFixed(2)}');
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

/// Mudaram os itens (nome, quantidade, preço), o `cliente_id` ou o
/// `cliente_nome`? É o que tira um pedido de `pronto` no servidor.
/// O nome é comparado exatamente como vai ao servidor (null e '' diferem):
/// na dúvida conta como mudança, que só pede uma assinatura a mais.
bool itensOuClienteMudaram(Map antes, Map depois) =>
    !mesmosItens(antes['produtos'], depois['produtos']) ||
    _inteiro(antes['cliente_id']) != _inteiro(depois['cliente_id']) ||
    antes['cliente_nome']?.toString() != depois['cliente_nome']?.toString();

bool _temAssinatura(Object? v) =>
    v is List ? v.isNotEmpty : (v != null && '$v'.trim().isNotEmpty);

/// Salvar [editado] pede a assinatura do pedido de novo?
/// - [original] é rascunho só do aparelho (`so_local = 1`): o envio pede;
/// - [original] não tem assinatura do pedido (nem bytes nem arquivo);
/// - mudaram os itens ou o cliente ([itensOuClienteMudaram]).
bool precisaAssinaturaDoPedido({required Map original, required Map editado}) =>
    _verdadeiro(original['so_local']) ||
    !(_temAssinatura(original['assinatura_pedido']) ||
        _temAssinatura(original['assinatura_pedido_path'])) ||
    itensOuClienteMudaram(original, editado);
