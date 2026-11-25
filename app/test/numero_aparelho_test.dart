import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('numero_aparelho_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  setUp(_limpar);
  tearDownAll(_limpar);

  test('numeroUsadoNoAparelho: mesmo numero e vendedor em outra linha, so o mesmo numero ou outro vendedor nao', () async {
    final id = await salvarPedidoLocal({
      'numero': '50',
      'vendedor_codigo': '0001',
      'produtos': [],
      'total': 0,
      'status': 'salvo',
    });

    expect(await numeroUsadoNoAparelho('50', '0001'), isTrue);
    expect(await numeroUsadoNoAparelho('51', '0001'), isFalse);
    expect(await numeroUsadoNoAparelho('50', '0002'), isFalse);
    // a própria linha não conta como "outra"
    expect(await numeroUsadoNoAparelho('50', '0001', ignorarId: id), isFalse);
  });

  test('numeroUsadoNoAparelho sem nenhum pedido: false', () async {
    expect(await numeroUsadoNoAparelho('1', '0001'), isFalse);
  });
}
