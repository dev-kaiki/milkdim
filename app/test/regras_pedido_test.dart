import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

void main() {
  group('podeTrocarNumero', () {
    test('qualquer status com erro_envio numero', () {
      for (final st in ['salvo', 'finalizado', 'cancelado']) {
        expect(podeTrocarNumero({'status': st, 'erro_envio': 'numero'}), isTrue);
      }
    });
    test('sem erro ou outro erro: nao', () {
      expect(podeTrocarNumero({'status': 'finalizado'}), isFalse);
      expect(podeTrocarNumero({'erro_envio': 'outro'}), isFalse);
    });
  });

  group('gravacaoEhAviso', () {
    test('numeroEmUso e fechadoNoControle sao avisos', () {
      expect(gravacaoEhAviso(ResultadoGravacao.numeroEmUso), isTrue);
      expect(gravacaoEhAviso(ResultadoGravacao.fechadoNoControle), isTrue);
      expect(gravacaoEhAviso(ResultadoGravacao.canceladoNoControle), isTrue);
      expect(gravacaoEhAviso(ResultadoGravacao.enviado), isFalse);
      expect(gravacaoEhAviso(ResultadoGravacao.pendente), isFalse);
    });
  });

  group('proximoNumeroLivre', () {
    test('devolve o primeiro livre', () async {
      final r = await proximoNumeroLivre(10, (n) async => n == '12');
      expect(r, '12');
    });
    test('livre de cara', () async {
      expect(await proximoNumeroLivre(5, (_) async => true), '5');
    });
    test('null depois de 20 tentativas', () async {
      var chamadas = 0;
      final r = await proximoNumeroLivre(1, (_) async {
        chamadas++;
        return false;
      });
      expect(r, isNull);
      expect(chamadas, 20);
    });
    test('o 21o numero nao e tentado', () async {
      expect(await proximoNumeroLivre(1, (n) async => n == '21'), isNull);
      expect(await proximoNumeroLivre(1, (n) async => n == '20'), '20');
    });
  });

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
    test('canceladoNoControle', () {
      expect(mensagemGravacao(ResultadoGravacao.canceladoNoControle, 'salvo'),
          'Este pedido foi cancelado no Controle.');
    });
    test('numeroEmUso', () {
      expect(mensagemGravacao(ResultadoGravacao.numeroEmUso, 'salvo'),
          'Número já usado; troque o número');
    });
    test('rascunho: sem mensagem', () {
      expect(mensagemGravacao(ResultadoGravacao.rascunho, 'salvo'), isNull);
    });
  });

  group('apagado no Controle', () {
    test('apagadoNoControle so com erro_envio apagado', () {
      expect(apagadoNoControle({'id': 492, 'status': 'finalizado', 'erro_envio': 'apagado'}),
          isTrue);
      expect(apagadoNoControle({'id': 492, 'status': 'salvo', 'erro_envio': kErroApagadoNoControle}),
          isTrue);
      expect(apagadoNoControle({'id': 492, 'status': 'salvo'}), isFalse);
      expect(apagadoNoControle({'id': 492, 'status': 'salvo', 'erro_envio': 'numero'}), isFalse);
    });
    test('qualquer status: so Apagar do aparelho', () {
      for (final st in ['salvo', 'pronto', 'finalizado', 'cancelado']) {
        final p = {'id': 492, 'status': st, 'so_local': 0, 'pendente_envio': 0,
          'erro_envio': 'apagado'};
        expect(acaoRemover(p), AcaoRemover.apagarDoAparelho, reason: st);
        expect(podeTrocarNumero(p), isFalse, reason: st);
      }
    });
    test('mensagem exata e e aviso', () {
      expect(mensagemGravacao(ResultadoGravacao.apagadoNoControle, 'salvo'),
          'Este pedido foi apagado no Controle.');
      expect(mensagemGravacao(ResultadoGravacao.apagadoNoControle, 'finalizado'),
          'Este pedido foi apagado no Controle.');
      expect(gravacaoEhAviso(ResultadoGravacao.apagadoNoControle), isTrue);
    });
  });
}
