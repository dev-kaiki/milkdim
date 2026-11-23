import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

void main() {
  const idLocal = kLocalIdBase + 5;

  group('numeroEditavel', () {
    test('pedido que nunca chegou ao servidor: editavel', () {
      expect(numeroEditavel({'id': idLocal}), isTrue);
    });
    test('pedido do servidor: travado', () {
      expect(numeroEditavel({'id': 42}), isFalse);
    });
    test('pedido do servidor com conflito de numero: editavel', () {
      expect(numeroEditavel({'id': 42, 'erro_envio': 'numero'}), isTrue);
    });
    test('pedido do servidor com outro erro: travado', () {
      expect(numeroEditavel({'id': 42, 'erro_envio': 'outro'}), isFalse);
    });
  });

  group('acaoRemover', () {
    test('rascunho antigo so_local: apagar do aparelho', () {
      expect(acaoRemover({'id': idLocal, 'status': 'salvo', 'so_local': 1}),
          AcaoRemover.apagarDoAparelho);
    });
    test('salvo que ja chegou ao servidor: cancelar', () {
      expect(acaoRemover({'id': 42, 'status': 'salvo', 'so_local': 0}),
          AcaoRemover.cancelar);
    });
    test('salvo pendente de envio: cancelar', () {
      expect(
          acaoRemover(
              {'id': idLocal, 'status': 'salvo', 'so_local': 0, 'pendente_envio': 1}),
          AcaoRemover.cancelar);
    });
    test('finalizado: nenhuma', () {
      expect(acaoRemover({'id': 42, 'status': 'finalizado'}), AcaoRemover.nenhuma);
    });
    test('cancelado: nenhuma', () {
      expect(acaoRemover({'id': 42, 'status': 'cancelado'}), AcaoRemover.nenhuma);
    });
    test('salvo local, nao pendente e fora do servidor: nenhuma', () {
      expect(
          acaoRemover(
              {'id': idLocal, 'status': 'salvo', 'so_local': 0, 'pendente_envio': 0}),
          AcaoRemover.nenhuma);
    });
  });

  group('mensagemGravacao', () {
    test('enviado + salvo', () {
      expect(mensagemGravacao(ResultadoGravacao.enviado, 'salvo'),
          'Pedido enviado para produção.');
    });
    test('enviado + finalizado: sem mensagem nova', () {
      expect(mensagemGravacao(ResultadoGravacao.enviado, 'finalizado'), isNull);
    });
    test('pendente', () {
      expect(mensagemGravacao(ResultadoGravacao.pendente, 'salvo'),
          'Pedido salvo. Será enviado quando houver internet.');
    });
    test('fechadoNoControle', () {
      expect(mensagemGravacao(ResultadoGravacao.fechadoNoControle, 'salvo'),
          'Este pedido já foi finalizado no Controle.');
    });
    test('numeroEmUso', () {
      expect(mensagemGravacao(ResultadoGravacao.numeroEmUso, 'salvo'),
          'Número já usado; troque o número');
    });
    test('rascunho: sem mensagem', () {
      expect(mensagemGravacao(ResultadoGravacao.rascunho, 'salvo'), isNull);
    });
  });
}
