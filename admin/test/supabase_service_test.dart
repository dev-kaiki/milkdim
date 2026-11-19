import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/services/supabase_service.dart';

const _proibidas = [
  'código',
  'preço',
  'número',
  'WhatsApp',
  'e-mail',
  'nome_do_cliente',
  'descrição',
];

List<String> _colunas(String filtro) =>
    filtro.split(',').map((p) => p.split('.').first).toList();

void _semProibidas(String filtro) {
  for (final p in _proibidas) {
    expect(filtro.contains(p), isFalse, reason: 'contem "$p": $filtro');
  }
}

void main() {
  test('filtroBuscaClientes usa so colunas reais', () {
    final f = filtroBuscaClientes('t');
    expect(
      f,
      'nome.ilike.%t%,nome_fantasia.ilike.%t%,cpf_cnpj.ilike.%t%,'
      'telefone.ilike.%t%,cidade.ilike.%t%,whatsapp.ilike.%t%,email.ilike.%t%',
    );
    expect(
      _colunas(f).toSet(),
      {'nome', 'nome_fantasia', 'cpf_cnpj', 'telefone', 'cidade', 'whatsapp', 'email'},
    );
    _semProibidas(f);
  });

  test('filtroBuscaProdutos usa nome, descricao e codigo', () {
    final f = filtroBuscaProdutos('leite');
    expect(f, 'nome.ilike.%leite%,descricao.ilike.%leite%,codigo.ilike.%leite%');
    _semProibidas(f);
  });

  test('filtroBuscaVendedores usa nome e codigo', () {
    final f = filtroBuscaVendedores('0003');
    expect(f, 'nome.ilike.%0003%,codigo.ilike.%0003%');
    _semProibidas(f);
  });

  test('filtroBuscaPedidos usa so colunas reais', () {
    final f = filtroBuscaPedidos('ana');
    expect(
      f,
      'vendedor_nome.ilike.%ana%,cliente_nome.ilike.%ana%,'
      'cliente_nome_fantasia.ilike.%ana%,numero.ilike.%ana%',
    );
    _semProibidas(f);
  });
}
