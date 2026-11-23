// Regras puras do fluxo do pedido (sem Flutter nem banco), usadas pelas telas.
import 'db.dart' show jaChegouAoServidor, kErroNumeroEmUso;
import 'supabase_helper.dart' show ResultadoGravacao;

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
    case ResultadoGravacao.numeroEmUso:
      return kMsgNumeroEmUso;
    case ResultadoGravacao.rascunho:
      return null;
  }
}
