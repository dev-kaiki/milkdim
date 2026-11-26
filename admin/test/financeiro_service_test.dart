import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/services/financeiro_service.dart';

void main() {
  test('filtroEntregues converte as bordas locais para UTC', () {
    final f = FinanceiroService.filtroEntregues(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    expect(DateTime.parse(f.de), DateTime(2026, 11, 1).toUtc());
    expect(DateTime.parse(f.ate), DateTime(2026, 12, 1).toUtc());
    expect(f.de.endsWith('Z'), isTrue);
  });
  test('entregue 30/11 23:30 local cai dentro de novembro', () {
    final f = FinanceiroService.filtroEntregues(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final t = DateTime(2026, 11, 30, 23, 30).toUtc();
    expect(!t.isBefore(DateTime.parse(f.de)) && t.isBefore(DateTime.parse(f.ate)), isTrue);
  });
  test('filtroSaidas usa datas', () {
    final f = FinanceiroService.filtroSaidas(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    expect(f.de, '2026-11-01');
    expect(f.ate, '2026-12-01');
  });
}
