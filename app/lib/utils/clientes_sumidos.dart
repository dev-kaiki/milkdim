// Clientes sumidos: quem não compra há [prazoDias] dias ou mais, e os links
// de contato (WhatsApp e ligação). Só leitura; nada aqui altera pedidos.
import 'regras_pedido.dart' show apagadoNoControle;

/// Prazos oferecidos na tela (dias sem comprar); o primeiro é o padrão.
const List<int> kPrazosSumido = [30, 60, 90];

class ClienteSumido {
  final Map<String, dynamic> cliente;
  final DateTime ultimaCompra;
  final int dias;
  final int pedidos;

  const ClienteSumido({
    required this.cliente,
    required this.ultimaCompra,
    required this.dias,
    required this.pedidos,
  });
}

int? _inteiro(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());

/// Clientes cujo último pedido válido do vendedor tem [prazoDias] dias ou mais,
/// do menos para o mais dias. Pedido válido: do vendedor, não cancelado e não
/// apagado no Controle. `dias` conta dias de calendário local.
List<ClienteSumido> clientesSumidos({
  required List<Map<String, dynamic>> clientes,
  required List<Map<String, dynamic>> pedidos,
  required String vendedorCodigo,
  required DateTime agora,
  int prazoDias = 30,
}) {
  final ultima = <int, DateTime>{};
  final contagem = <int, int>{};
  for (final p in pedidos) {
    if ('${p['vendedor_codigo'] ?? ''}'.trim() != vendedorCodigo.trim()) continue;
    if ('${p['status'] ?? ''}'.trim().toLowerCase() == 'cancelado') continue;
    if (apagadoNoControle(p)) continue;
    final id = _inteiro(p['cliente_id']);
    if (id == null) continue;
    final DateTime data;
    try {
      data = DateTime.parse('${p['datahora']}').toLocal();
    } catch (_) {
      continue;
    }
    contagem[id] = (contagem[id] ?? 0) + 1;
    final atual = ultima[id];
    if (atual == null || data.isAfter(atual)) ultima[id] = data;
  }

  final hoje = DateTime(agora.year, agora.month, agora.day);
  final out = <ClienteSumido>[];
  for (final c in clientes) {
    final id = _inteiro(c['id']);
    final data = id == null ? null : ultima[id];
    if (id == null || data == null) continue;
    final dia = DateTime(data.year, data.month, data.day);
    // Diferença em dias de calendário (arredonda por causa da virada de horário de verão).
    final dias = (hoje.difference(dia).inHours / 24).round();
    if (dias < prazoDias) continue;
    out.add(ClienteSumido(
        cliente: c, ultimaCompra: data, dias: dias, pedidos: contagem[id] ?? 0));
  }
  out.sort((a, b) => a.dias.compareTo(b.dias));
  return out;
}

/// Telefone só com dígitos, com DDI 55: 10 ou 11 dígitos ganham "55"; 12 ou 13
/// começando com "55" ficam como estão; o resto é inválido (null).
String? normalizarTelefone(String? bruto) {
  final d = (bruto ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 10 || d.length == 11) return '55$d';
  if ((d.length == 12 || d.length == 13) && d.startsWith('55')) return d;
  return null;
}

String _primeiroValido(Map<String, dynamic> c, List<String> campos) {
  for (final k in campos) {
    final n = normalizarTelefone(c[k]?.toString());
    if (n != null) return n;
  }
  return '';
}

/// `https://wa.me/<num>?text=...` com o `whatsapp` do cliente (ou o `telefone`
/// se o whatsapp for inválido); null se nenhum servir.
Uri? linkWhatsApp(Map<String, dynamic> cliente, String mensagem) {
  final n = _primeiroValido(cliente, ['whatsapp', 'telefone']);
  if (n.isEmpty) return null;
  return Uri.https('wa.me', '/$n', {'text': mensagem});
}

/// `tel:<num>` com o `telefone` do cliente (ou o `whatsapp` se o telefone for
/// inválido); null se nenhum servir.
Uri? linkLigar(Map<String, dynamic> cliente) {
  final n = _primeiroValido(cliente, ['telefone', 'whatsapp']);
  if (n.isEmpty) return null;
  return Uri(scheme: 'tel', path: n);
}

String mensagemSumido(String nomeVendedor) =>
    'Olá! Aqui é o $nomeVendedor da MilkDim. Faz um tempinho que a gente não se '
    'fala, posso passar aí essa semana?';
