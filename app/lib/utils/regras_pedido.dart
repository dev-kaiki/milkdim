// Regras puras do fluxo do pedido (sem Flutter nem banco), usadas pelas telas.
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

AcaoRemover acaoRemover(Map<String, dynamic> p) {
  if ((p['status'] ?? '').toString().toLowerCase() != 'salvo') return AcaoRemover.nenhuma;
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
