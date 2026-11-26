import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/services/caixas_service.dart';

/// FonteCaixas em memória para os testes de widget.
class FonteCaixasFalsa implements FonteCaixas {
  FonteCaixasFalsa({
    this.tipos = const [],
    this.salvos,
    this.falhaTipos = false,
    this.falhaSalvar,
    this.log,
  });

  final List<TipoCaixa> tipos;
  final VolumesPedido? salvos;
  final bool falhaTipos;
  final Object? falhaSalvar;
  final List<String>? log;
  final List<VolumesPedido> gravados = [];

  @override
  Future<List<TipoCaixa>> tiposCaixa() async {
    if (falhaTipos) throw Exception('tabela inexistente');
    return tipos;
  }

  @override
  Future<VolumesPedido?> volumesSalvos(int pedidoId) async => salvos;

  @override
  Future<void> salvarVolumes(int pedidoId, VolumesPedido v) async {
    log?.add('salvar');
    if (falhaSalvar != null) throw falhaSalvar!;
    gravados.add(v);
  }

  @override
  Future<void> criarTipo(String nome, int capacidade, bool mistura) async {}
  @override
  Future<void> alterarTipo(TipoCaixa t) async {}
  @override
  Future<void> definirTipoDoProduto(int produtoId, int? tipoId) async {}
}
