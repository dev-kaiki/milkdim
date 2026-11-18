// test/envio_pendentes_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

Future<Map<String, Object?>?> _porId(int id) async {
  final db = await getDb();
  final r = await db.query('pedidos', where: 'id = ?', whereArgs: [id]);
  return r.isEmpty ? null : r.single;
}

Future<void> _finalizado(int id, String numero, String vend, String datahora,
    {double total = 0}) =>
    salvarPedidoLocal({
      'id': id,
      'numero': numero,
      'status': 'finalizado',
      'vendedor_codigo': vend,
      'datahora': datahora,
      'total': total,
    });

/// Simula o servidor confirmando o envio (o que salvarPedidoSupabase faz).
Future<void> _marcarEnviado(Map<String, dynamic> p) async {
  final db = await getDb();
  await db.update('pedidos', {'pendente_envio': 0}, where: 'id = ?', whereArgs: [p['id']]);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('envio_pendentes_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDownAll(_limpar);

  group('subirPedidosPendentes', () {
    setUp(() async {
      await _finalizado(kLocalIdBase + 1, '1', '0003', '2026-11-01T10:00:00Z');
      await _finalizado(kLocalIdBase + 2, '2', '0003', '2026-11-02T10:00:00Z');
      await _finalizado(kLocalIdBase + 3, '1', '0002', '2026-11-01T09:00:00Z');
    });

    test('envia so os pendentes do vendedor informado', () async {
      final chamados = <Map<String, dynamic>>[];
      final r = await subirPedidosPendentes(
        vendedorCodigo: '0003',
        enviar: (p) async {
          chamados.add(p);
          await _marcarEnviado(p);
        },
      );
      expect(chamados.length, 2);
      expect(chamados.every((p) => p['vendedor_codigo'] == '0003'), isTrue);
      expect(chamados.map((p) => p['numero']).toList(), ['1', '2']);
      expect(r.enviados, 2);
      expect(r.falhas, 0);
      expect(await contarPedidosPendentesEnvio('0003'), 0);
      expect(await contarPedidosPendentesEnvio('0002'), 1);
    });

    test('falha num pedido nao para os outros e o pedido continua pendente', () async {
      var n = 0;
      final r = await subirPedidosPendentes(
        vendedorCodigo: '0003',
        enviar: (p) async {
          n++;
          if (n == 2) throw Exception('sem internet');
          await _marcarEnviado(p);
        },
      );
      expect(r.enviados, 1);
      expect(r.falhas, 1);
      expect((await _porId(kLocalIdBase + 1))!['pendente_envio'], 0);
      expect((await _porId(kLocalIdBase + 2))!['pendente_envio'], 1);
    });

    test('continua depois de falhar no primeiro', () async {
      var n = 0;
      final r = await subirPedidosPendentes(
        vendedorCodigo: '0003',
        enviar: (p) async {
          n++;
          if (n == 1) throw Exception('erro');
          await _marcarEnviado(p);
        },
      );
      expect(n, 2);
      expect(r.enviados, 1);
      expect(r.falhas, 1);
      expect((await _porId(kLocalIdBase + 1))!['pendente_envio'], 1);
    });
  });

  group('aplicarPedidosRemotos', () {
    Map<String, dynamic> remoto(int id, String numero, String vend, {double total = 10}) => {
          'id': id,
          'numero': numero,
          'vendedor_codigo': vend,
          'status': 'finalizado',
          'total': total,
          'produtos': [],
          'datahora': '2026-11-10T10:00:00Z',
        };

    test('nao sobrescreve pedido local pendente com o mesmo id', () async {
      // Pedido já sincronizado (id do servidor) e editado offline depois.
      await _finalizado(5, '7', '0003', '2026-11-01T10:00:00Z', total: 99);
      await aplicarPedidosRemotos([remoto(5, '7', '0003', total: 10)]);
      final p = await _porId(5);
      expect(p!['total'], 99);
      expect(p['pendente_envio'], 1);
    });

    test('nao apaga pendente local com o mesmo (numero, vendedor) e outro id', () async {
      await _finalizado(kLocalIdBase + 1, '8', '0003', '2026-11-01T10:00:00Z', total: 50);
      await aplicarPedidosRemotos([remoto(6, '8', '0003')]);
      final p = await _porId(kLocalIdBase + 1);
      expect(p, isNotNull);
      expect(p!['total'], 50);
      expect(p['pendente_envio'], 1);
      expect(await _porId(6), isNull);
    });

    test('aplica remotos sem conflito e substitui pedido local ja enviado', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 9, 'numero': '9', 'vendedor_codigo': '0003', 'status': 'finalizado',
        'total': 1.0, 'pendente_envio': 0,
      });
      await aplicarPedidosRemotos([
        remoto(9, '9', '0003', total: 2),
        remoto(11, '11', '0003', total: 3),
      ]);
      expect((await _porId(9))!['total'], 2);
      expect((await _porId(11))!['total'], 3);
      expect((await _porId(11))!['pendente_envio'], 0);
    });

    test('continua protegendo rascunho com id colidindo', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 10, 'numero': '20', 'vendedor_codigo': '0003', 'status': 'salvo', 'total': 4.0,
      });
      await aplicarPedidosRemotos([remoto(10, '10', '0003', total: 7)]);
      expect((await _porId(10))!['total'], 7);
      final rasc = await db.query('pedidos', where: "numero = '20'");
      expect(rasc.single['status'], 'salvo');
      expect(rasc.single['id'] as int, greaterThanOrEqualTo(kLocalIdBase));
    });
  });
}
