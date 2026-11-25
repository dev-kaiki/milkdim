-- MilkDim, fase D: financeiro do Controle (saidas e categorias de saida).
--
-- Roda depois de 20261124000001_fase_b_etiqueta_qr.sql.
--
-- Tabelas novas:
--   categorias_saida  categorias das saidas (Materia-prima, Embalagens, ...).
--                     Nome unico sem contar maiusculas nem espacos nas pontas.
--                     Categoria com saidas nao e apagada (on delete restrict):
--                     o app so a desativa (ativa = false).
--   saidas            o que a fabrica gastou: data, categoria, descricao, valor.
--
-- A fase so LE pedidos: nenhuma coluna nem gatilho de pedidos muda aqui.
--
-- Auditoria: o gatilho saidas_auditoria preenche criado_* e alterado_* com
-- now() e public.app_autor_pedido(), e ignora o que o cliente mandar. Sem
-- JWT (SQL Editor) o autor fica nulo. A funcao e security definer com
-- search_path vazio porque app_autor_pedido nao e executavel por
-- authenticated.
--
-- Permissoes: so admin (public.app_is_admin()) le e escreve nas duas
-- tabelas; anon nao tem acesso nenhum; vendedor comum ve zero linhas.
--
-- Dados iniciais: as 8 categorias, so se ainda nao existirem.
--
-- Pode rodar de novo sem estrago (if not exists / drop ... if exists /
-- on conflict do nothing). Este arquivo nao abre nem fecha transacao: quem
-- aplica decide.

-- ---------------------------------------------------------------------------
-- categorias_saida
-- ---------------------------------------------------------------------------

create table if not exists public.categorias_saida (
  id    bigint generated always as identity primary key,
  nome  text    not null,
  ativa boolean not null default true,
  ordem int     not null default 100
);

create unique index if not exists categorias_saida_nome_key
  on public.categorias_saida (lower(btrim(nome)));

-- ---------------------------------------------------------------------------
-- saidas
-- ---------------------------------------------------------------------------

create table if not exists public.saidas (
  id           bigint generated always as identity primary key,
  data         date          not null,
  categoria_id bigint        not null
               references public.categorias_saida (id) on delete restrict,
  descricao    text          not null default '',
  valor        numeric(12,2) not null check (valor > 0),
  criado_em    timestamptz,
  criado_por   text,
  alterado_em  timestamptz,
  alterado_por text
);

create index if not exists saidas_data_idx on public.saidas (data);

-- ---------------------------------------------------------------------------
-- Auditoria (BEFORE INSERT OR UPDATE)
-- ---------------------------------------------------------------------------
-- INSERT: criado_* e alterado_* recebem o mesmo valor, o do servidor.
-- UPDATE: criado_* voltam a ser os de OLD; alterado_* recebem now() e o autor.

create or replace function public.saidas_auditoria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.criado_em    := now();
    new.criado_por   := public.app_autor_pedido();
    new.alterado_em  := new.criado_em;
    new.alterado_por := new.criado_por;
  else
    new.criado_em    := old.criado_em;
    new.criado_por   := old.criado_por;
    new.alterado_em  := now();
    new.alterado_por := public.app_autor_pedido();
  end if;

  return new;
end;
$$;

revoke execute on function public.saidas_auditoria() from public, anon, authenticated;

drop trigger if exists saidas_auditoria on public.saidas;
create trigger saidas_auditoria
  before insert or update on public.saidas
  for each row execute function public.saidas_auditoria();

-- ---------------------------------------------------------------------------
-- Permissoes: so admin
-- ---------------------------------------------------------------------------

alter table public.categorias_saida enable row level security;
alter table public.saidas           enable row level security;

drop policy if exists categorias_saida_admin on public.categorias_saida;
create policy categorias_saida_admin on public.categorias_saida
  for all to authenticated
  using (public.app_is_admin())
  with check (public.app_is_admin());

drop policy if exists saidas_admin on public.saidas;
create policy saidas_admin on public.saidas
  for all to authenticated
  using (public.app_is_admin())
  with check (public.app_is_admin());

revoke all on public.categorias_saida from anon;
revoke all on public.saidas           from anon;

grant select, insert, update, delete on public.categorias_saida to authenticated;
grant select, insert, update, delete on public.saidas           to authenticated;

-- ---------------------------------------------------------------------------
-- Dados iniciais
-- ---------------------------------------------------------------------------
-- Roda como dono da tabela (migracao), sem passar pela RLS. O conflito e
-- sobre o indice unico do nome: de novo, nao duplica.

insert into public.categorias_saida (nome, ordem) values
  ('Matéria-prima',                         1),
  ('Embalagens',                            2),
  ('Combustível/entrega',                   3),
  ('Salários',                              4),
  ('Aluguel/contas (água, luz, gás)',       5),
  ('Impostos',                              6),
  ('Manutenção',                            7),
  ('Outros',                                8)
on conflict ((lower(btrim(nome)))) do nothing;
