// Regras dos volumes (caixas) de um pedido. Dart puro, sem Flutter.
//
// O servidor (RPC pedido_salvar_volumes) compara os itens por btrim(nome),
// diferenciando maiúsculas. Por isso o nome do item no volume é o do pedido,
// sem normalizar, e a conferência soma por nome com trim apenas. A
// normalização (trim + minúsculas) só serve para ligar item a produto.
import '../models/pedido.dart';
import '../models/produto.dart';

class TipoCaixa {
  final int id;
  final String nome;
  final int capacidade;
  final bool misturaSabores;
  final bool ativo;

  const TipoCaixa({
    required this.id,
    required this.nome,
    required this.capacidade,
    required this.misturaSabores,
    required this.ativo,
  });

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString().trim() ?? '') ?? 0;
  }

  static bool _toBool(dynamic v, {required bool padrao}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 't';
    }
    return padrao;
  }

  factory TipoCaixa.fromMap(Map<String, dynamic> m) => TipoCaixa(
        id: _toInt(m['id']),
        nome: (m['nome'] ?? '').toString(),
        capacidade: _toInt(m['capacidade']),
        misturaSabores: _toBool(m['mistura_sabores'], padrao: true),
        ativo: _toBool(m['ativo'], padrao: true),
      );
}

class ItemVolume {
  final String nome;
  final int quantidade;

  const ItemVolume({required this.nome, required this.quantidade});
}

class Volume {
  /// true = caixa de um tipo; false = avulsos.
  final bool caixa;
  final String? tipoNome;
  final List<ItemVolume> itens;

  const Volume({required this.caixa, required this.tipoNome, required this.itens});

  /// Formato esperado pela RPC pedido_salvar_volumes.
  Map<String, dynamic> toJson() => {
        'tipo': caixa ? 'caixa' : 'avulso',
        'caixa': caixa ? tipoNome : null,
        'itens': [
          for (final i in itens) {'nome': i.nome, 'quantidade': i.quantidade}
        ],
      };

  factory Volume.fromJson(Map<String, dynamic> j) {
    final ehCaixa = j['tipo'] == 'caixa';
    return Volume(
      caixa: ehCaixa,
      tipoNome: ehCaixa ? j['caixa']?.toString() : null,
      itens: [
        for (final e in (j['itens'] as List? ?? const []))
          ItemVolume(
            nome: ((e as Map)['nome'] ?? '').toString(),
            quantidade: TipoCaixa._toInt(e['quantidade']),
          )
      ],
    );
  }
}

class VolumesPedido {
  /// Pedido solto: um único volume avulso com tudo, sem numeração.
  final bool solto;

  /// Caixas primeiro, avulsos por último.
  final List<Volume> volumes;

  const VolumesPedido({required this.solto, required this.volumes});
}

/// Nome normalizado para ligar item a produto: trim + minúsculas.
String chaveNome(String nome) => nome.trim().toLowerCase();

/// Tipo de caixa por nome (normalizado) de produto. Com vários produtos de
/// mesmo nome vale o ativo de menor id; sem ativo, o inativo de menor id.
/// O valor é null sem tipo, ou com tipo inativo/inexistente.
Map<String, TipoCaixa?> tiposPorNomeDeProduto(
    List<Produto> produtos, List<TipoCaixa> tipos) {
  final escolhido = <String, Produto>{};
  for (final p in produtos) {
    final k = chaveNome(p.nome);
    final atual = escolhido[k];
    if (atual == null) {
      escolhido[k] = p;
      continue;
    }
    final melhor = (p.ativo && !atual.ativo) ||
        (p.ativo == atual.ativo && p.id < atual.id);
    if (melhor) escolhido[k] = p;
  }
  final porId = {for (final t in tipos) t.id: t};
  return {
    for (final e in escolhido.entries)
      e.key: () {
        final t = e.value.tipoCaixaId == null ? null : porId[e.value.tipoCaixaId];
        return (t != null && t.ativo) ? t : null;
      }()
  };
}

/// Soma por nome com trim (como o btrim do servidor), na ordem da primeira
/// ocorrência. O nome guardado é o da primeira ocorrência, como veio.
/// Ignora quantidade <= 0.
Map<String, ({String nome, int quantidade})> _somarPorNome(
    Iterable<({String nome, int quantidade})> linhas) {
  final out = <String, ({String nome, int quantidade})>{};
  for (final l in linhas) {
    if (l.quantidade <= 0) continue;
    final k = l.nome.trim();
    final a = out[k];
    out[k] = (nome: a?.nome ?? l.nome, quantidade: (a?.quantidade ?? 0) + l.quantidade);
  }
  return out;
}

VolumesPedido sugerirVolumes(
    List<PedidoItem> itens, Map<String, TipoCaixa?> tipos) {
  final somados = _somarPorNome(
      itens.map((i) => (nome: i.nome, quantidade: i.quantidade))).values.toList();

  // Itens por tipo, na ordem do primeiro item de cada tipo.
  final grupos = <int, List<({String nome, int quantidade})>>{};
  final tipoDoId = <int, TipoCaixa>{};
  final avulsos = <String, int>{}; // chave: nome trim; ordem de inserção
  final nomeAvulso = <String, String>{};
  void addAvulso(String nome, int q) {
    if (q <= 0) return;
    final k = nome.trim();
    nomeAvulso.putIfAbsent(k, () => nome);
    avulsos[k] = (avulsos[k] ?? 0) + q;
  }

  for (final it in somados) {
    final t = tipos[chaveNome(it.nome)];
    if (t == null || !t.ativo || t.capacidade <= 0) {
      addAvulso(it.nome, it.quantidade);
      continue;
    }
    tipoDoId[t.id] = t;
    grupos.putIfAbsent(t.id, () => []).add(it);
  }

  final caixas = <Volume>[];
  // sobra de cada item (por nome trim) de itens em caixas
  final sobras = <String, int>{};
  for (final entry in grupos.entries) {
    final t = tipoDoId[entry.key]!;
    final lista = entry.value;
    if (t.misturaSabores) {
      final total = lista.fold<int>(0, (s, e) => s + e.quantidade);
      final nCaixas = total ~/ t.capacidade;
      var idx = 0;
      var restante = lista.isEmpty ? 0 : lista[0].quantidade;
      for (var c = 0; c < nCaixas; c++) {
        var falta = t.capacidade;
        final doVolume = <ItemVolume>[];
        while (falta > 0) {
          while (restante == 0) {
            idx++;
            restante = lista[idx].quantidade;
          }
          final tira = restante < falta ? restante : falta;
          doVolume.add(ItemVolume(nome: lista[idx].nome, quantidade: tira));
          restante -= tira;
          falta -= tira;
        }
        caixas.add(Volume(caixa: true, tipoNome: t.nome, itens: doVolume));
      }
      // o que sobrou: resto do item atual e todos os seguintes
      if (nCaixas == 0) {
        for (final e in lista) {
          sobras[e.nome.trim()] = e.quantidade;
        }
      } else {
        sobras[lista[idx].nome.trim()] = restante;
        for (var j = idx + 1; j < lista.length; j++) {
          sobras[lista[j].nome.trim()] = lista[j].quantidade;
        }
      }
    } else {
      for (final e in lista) {
        final n = e.quantidade ~/ t.capacidade;
        for (var c = 0; c < n; c++) {
          caixas.add(Volume(
            caixa: true,
            tipoNome: t.nome,
            itens: [ItemVolume(nome: e.nome, quantidade: t.capacidade)],
          ));
        }
        sobras[e.nome.trim()] = e.quantidade % t.capacidade;
      }
    }
  }

  // Avulsos na ordem dos itens do pedido: sem caixa inteiros, com caixa só a sobra.
  final itensAvulsos = <ItemVolume>[];
  for (final it in somados) {
    final k = it.nome.trim();
    final q = (avulsos[k] ?? 0) + (sobras[k] ?? 0);
    if (q > 0) itensAvulsos.add(ItemVolume(nome: it.nome, quantidade: q));
  }

  return VolumesPedido(solto: false, volumes: [
    ...caixas,
    if (itensAvulsos.isNotEmpty)
      Volume(caixa: false, tipoNome: null, itens: itensAvulsos),
  ]);
}

/// Um volume avulso com todos os itens do pedido (sem numeração no rótulo).
VolumesPedido pedidoSolto(List<PedidoItem> itens) {
  final somados = _somarPorNome(
      itens.map((i) => (nome: i.nome, quantidade: i.quantidade))).values;
  return VolumesPedido(solto: true, volumes: [
    Volume(caixa: false, tipoNome: null, itens: [
      for (final s in somados) ItemVolume(nome: s.nome, quantidade: s.quantidade)
    ]),
  ]);
}

/// Lista vazia = os volumes batem com o pedido.
List<String> conferirVolumes(List<PedidoItem> itens, VolumesPedido v) {
  final pedido = _somarPorNome(
      itens.map((i) => (nome: i.nome, quantidade: i.quantidade)));
  final nosVolumes = _somarPorNome([
    for (final vol in v.volumes)
      for (final i in vol.itens) (nome: i.nome, quantidade: i.quantidade)
  ]);

  final msgs = <String>[];
  final nomes = <String>[...pedido.keys, ...nosVolumes.keys.where((k) => !pedido.containsKey(k))];
  for (final k in nomes) {
    final esperado = pedido[k]?.quantidade ?? 0;
    final tem = nosVolumes[k]?.quantidade ?? 0;
    final nome = k;
    if (tem < esperado) {
      msgs.add('$nome: faltam ${esperado - tem}');
    } else if (tem > esperado) {
      msgs.add('$nome: sobram ${tem - esperado}');
    }
  }
  for (var i = 0; i < v.volumes.length; i++) {
    final vol = v.volumes[i];
    if (vol.itens.isEmpty) {
      msgs.add(vol.caixa ? 'Caixa ${i + 1} está vazia' : 'Avulsos está vazio');
    }
  }
  return msgs;
}

bool volumesValem(List<PedidoItem> itens, VolumesPedido salvos) =>
    conferirVolumes(itens, salvos).isEmpty;

/// Rótulo do volume. [indice] começa em 0.
String rotuloVolume(VolumesPedido v, int indice) {
  if (v.solto) return 'Pedido solto';
  final vol = v.volumes[indice];
  final pos = '${indice + 1}/${v.volumes.length}';
  return vol.caixa ? 'Caixa $pos · ${vol.tipoNome ?? ''}' : 'Avulsos $pos';
}

/// Avisos (não bloqueiam) de caixa com mais unidades do que cabem.
/// [tiposPorNome] é indexado por TipoCaixa.nome.
List<String> avisosCapacidade(
    VolumesPedido v, Map<String, TipoCaixa> tiposPorNome) {
  final out = <String>[];
  if (v.solto) return out;
  for (var i = 0; i < v.volumes.length; i++) {
    final vol = v.volumes[i];
    if (!vol.caixa) continue;
    final t = tiposPorNome[vol.tipoNome];
    if (t == null) continue;
    final total = vol.itens.fold<int>(0, (s, e) => s + e.quantidade);
    if (total > t.capacidade) {
      out.add('Caixa ${i + 1}/${v.volumes.length} tem $total unidades (cabem ${t.capacidade})');
    }
  }
  return out;
}
