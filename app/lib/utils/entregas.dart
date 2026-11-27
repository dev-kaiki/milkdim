import 'clientes_sumidos.dart';
import 'regras_pedido.dart';

const String _semCidade = 'Sem cidade';

/// Pedidos prontos de uma mesma cidade.
class GrupoEntrega {
  final String cidade;
  final List<Map<String, dynamic>> pedidos;
  const GrupoEntrega({required this.cidade, required this.pedidos});
}

String _texto(Object? v) => '${v ?? ''}'.trim();

bool _entra(Map<String, dynamic> p, String vendedorCodigo) =>
    estaPronto(p) &&
    !apagadoNoControle(p) &&
    _texto(p['vendedor_codigo']) == vendedorCodigo.trim();

/// O cliente do pedido, com as chaves que `nomeExibicao` e `linkWhatsApp` leem.
Map<String, dynamic> clienteDoPedido(Map<String, dynamic> pedido) => {
      'whatsapp': pedido['cliente_whatsapp'],
      'telefone': pedido['cliente_telefone'],
      'nome': pedido['cliente_nome'],
      'nome_fantasia': pedido['cliente_nome_fantasia'],
      'cidade': pedido['cliente_cidade'],
    };

int _porNumero(Object? a, Object? b) {
  final na = int.tryParse(_texto(a));
  final nb = int.tryParse(_texto(b));
  if (na != null && nb != null) return na.compareTo(nb);
  return _texto(a).compareTo(_texto(b));
}

/// Pedidos prontos do vendedor (sem os apagados no Controle), agrupados por
/// cidade. Grupos em ordem alfabética, "Sem cidade" por último; dentro do
/// grupo, por nome do cliente e, no empate, pelo número do pedido.
List<GrupoEntrega> entregasProntas(
  List<Map<String, dynamic>> pedidos, {
  required String vendedorCodigo,
}) {
  final porChave = <String, List<Map<String, dynamic>>>{};
  final titulo = <String, String>{};
  for (final p in pedidos) {
    if (!_entra(p, vendedorCodigo)) continue;
    final cidade = _texto(p['cliente_cidade']);
    final chave = cidade.toLowerCase();
    titulo.putIfAbsent(chave, () => cidade.isEmpty ? _semCidade : cidade);
    porChave.putIfAbsent(chave, () => []).add(p);
  }
  final chaves = porChave.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.compareTo(b);
    });
  return [
    for (final k in chaves)
      GrupoEntrega(
        cidade: titulo[k]!,
        pedidos: porChave[k]!
          ..sort((a, b) {
            final c = nomeExibicao(clienteDoPedido(a))
                .toLowerCase()
                .compareTo(nomeExibicao(clienteDoPedido(b)).toLowerCase());
            return c != 0 ? c : _porNumero(a['numero'], b['numero']);
          }),
      ),
  ];
}

/// Quantos pedidos entram na lista de entregas.
int contarProntos(
  List<Map<String, dynamic>> pedidos, {
  required String vendedorCodigo,
}) =>
    pedidos.where((p) => _entra(p, vendedorCodigo)).length;

/// Busca no Google Maps por "endereço, cidade, CEP"; null sem endereço.
Uri? linkMapa(Map<String, dynamic> pedido) {
  final endereco = _texto(pedido['cliente_endereco']);
  if (endereco.isEmpty) return null;
  final partes = [
    endereco,
    _texto(pedido['cliente_cidade']),
    _texto(pedido['cliente_cep']),
  ].where((s) => s.isNotEmpty).join(', ');
  return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(partes)}');
}

/// Texto do WhatsApp avisando que o pedido está pronto.
String mensagemPronto(String nomeVendedor, String numero) {
  final nome = nomeVendedor.trim();
  final quem = nome.isEmpty ? 'Aqui é da MilkDim' : 'Aqui é o $nome da MilkDim';
  return 'Olá! $quem. Seu pedido nº $numero está pronto, passo aí hoje.';
}
