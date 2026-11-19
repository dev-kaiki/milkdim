-- Preparo do teste da fase 3: o passo que a implantacao faz a mao entre a
-- fase 1 e a fase 3 -- uma conta de admin para cada linha de acesso_admin.
-- Sem isto a guarda do inicio da fase 3 cancela a migracao.
--
-- Ordem de uma rodada (tudo numa chamada, desfeita no fim):
--   begin; <fase 1>; <este arquivo>; <fase 3>; <fase3_test.sql>; rollback;
--
-- Roda sem JWT, como no SQL Editor (app_migrar_admin recusa com JWT).

select public.app_migrar_admin('teste_admin_' || a.id, a.id)
  from public.acesso_admin a
 order by a.id;
