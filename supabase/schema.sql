-- 정보 탐정단 수업 앱 · Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 이 파일 전체를 붙여 넣고 Run 하면 된다. 여러 번 실행해도 안전하다.
-- 다른 앱과 한 프로젝트를 함께 쓰므로 이 앱의 테이블·함수는 모두 ud_ 로 시작한다(understanding-digital).
-- 이 파일은 ud_ 로 시작하는 것만 만들거나 바꾸고, 다른 테이블·함수는 건드리지 않는다.
--
-- 보안 모델
--   * 네 테이블 모두 RLS 를 켜고 anon/authenticated 에게는 정책을 하나도 주지 않는다.
--     → 익명 사용자는 테이블을 직접 읽거나 쓸 수 없다.
--   * 익명 사용자는 아래 security definer 함수(RPC)로만 접근한다.
--       쓰기: ud_submit_response, ud_submit_answer, ud_toggle_like   (존재하는 학급 코드일 때만)
--       읽기: ud_join_class, ud_class_summary                     (자기 학급 코드의 집계만)
--   * 교사는 학급 PIN 으로 ud_teacher_data 를 불러 학생 글 원문을 본다.
--   * 학급 만들기(ud_create_class)는 SQL Editor(서비스 역할)에서만 할 수 있다.
--   * 학생 개인정보는 모둠 번호와 별명만 받는다. client_id 는 기기에서 만든 임의의 값이다.

-- Supabase 는 pgcrypto 를 extensions 스키마에 미리 설치해 둔다. 그래서 함수마다 search_path 에 extensions 를 넣는다.
create extension if not exists pgcrypto with schema extensions;

-- ───────────── 테이블 ─────────────
create table if not exists public.ud_classes (
  code             text primary key check (code ~ '^[A-Za-z0-9-]{3,20}$'),
  name             text not null default '',
  teacher_pin_hash text not null,
  created_at       timestamptz not null default now()
);

create table if not exists public.ud_responses (
  id          uuid primary key default gen_random_uuid(),
  class_code  text not null references public.ud_classes(code) on delete cascade,
  client_id   uuid not null,
  group_no    text not null default '',
  nickname    text not null,
  mission     smallint not null check (mission between 0 and 4),
  item        text not null,
  value       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (class_code, client_id, mission, item)
);
create index if not exists ud_responses_class_idx on public.ud_responses (class_code, mission, item);

create table if not exists public.ud_board_answers (
  id          uuid primary key default gen_random_uuid(),
  class_code  text not null references public.ud_classes(code) on delete cascade,
  question_id uuid not null references public.ud_responses(id) on delete cascade,
  client_id   uuid not null,
  nickname    text not null,
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists ud_board_answers_q_idx on public.ud_board_answers (class_code, question_id);

create table if not exists public.ud_board_likes (
  question_id uuid not null references public.ud_responses(id) on delete cascade,
  class_code  text not null references public.ud_classes(code) on delete cascade,
  client_id   uuid not null,
  nickname    text not null,
  created_at  timestamptz not null default now(),
  primary key (question_id, client_id)
);

alter table public.ud_classes       enable row level security;
alter table public.ud_responses     enable row level security;
alter table public.ud_board_answers enable row level security;
alter table public.ud_board_likes   enable row level security;
-- 정책을 만들지 않으므로 anon/authenticated 는 직접 접근이 모두 막힌다.
revoke all on public.ud_classes, public.ud_responses, public.ud_board_answers, public.ud_board_likes from anon, authenticated;

-- ───────────── 내부 도우미 ─────────────
create or replace function public.ud_clean(t text, maxlen int)
returns text language sql immutable as $$
  select left(btrim(regexp_replace(coalesce(t, ''), '[[:cntrl:]]', ' ', 'g')), maxlen)
$$;

create or replace function public.ud_class_ok(p_code text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from ud_classes where code = p_code)
$$;

create or replace function public.ud_who(p_group text, p_nick text)
returns text language sql immutable as $$
  select case when coalesce(p_group, '') = '' then p_nick else p_group || '모둠 ' || p_nick end
$$;

-- ───────────── 교사용: 학급 만들기 (SQL Editor 에서만) ─────────────
create or replace function public.ud_create_class(p_code text, p_name text, p_pin text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_pin, '')) < 4 then raise exception 'PIN은 4자리 이상이어야 합니다'; end if;
  insert into ud_classes (code, name, teacher_pin_hash)
  values (upper(p_code), coalesce(p_name, ''), crypt(p_pin, gen_salt('bf')))
  on conflict (code) do update set name = excluded.name, teacher_pin_hash = excluded.teacher_pin_hash;
  return upper(p_code);
end $$;

-- ───────────── 학생: 입장 확인 ─────────────
create or replace function public.ud_join_class(p_code text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select coalesce(
    (select jsonb_build_object('ok', true, 'code', code, 'name', name) from ud_classes where code = upper(p_code)),
    jsonb_build_object('ok', false))
$$;

-- ───────────── 학생: 응답 저장 ─────────────
create or replace function public.ud_submit_response(
  p_code text, p_client uuid, p_group text, p_nick text, p_mission int, p_item text, p_value jsonb)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_nick text := ud_clean(p_nick, 20); v_code text := upper(p_code);
begin
  if not ud_class_ok(v_code) then raise exception 'unknown class'; end if;
  if v_nick = '' then raise exception 'nickname required'; end if;
  if p_mission not between 0 and 4 then raise exception 'bad mission'; end if;
  if p_item !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad item'; end if;
  if octet_length(p_value::text) > 6000 then raise exception 'value too large'; end if;

  insert into ud_responses (class_code, client_id, group_no, nickname, mission, item, value)
  values (v_code, p_client, ud_clean(p_group, 3), v_nick, p_mission, p_item, p_value)
  on conflict (class_code, client_id, mission, item) do update
    set value = excluded.value, group_no = excluded.group_no, nickname = excluded.nickname, updated_at = now()
  returning id into v_id;

  -- 이름표가 바뀌면 그 기기의 다른 응답에도 반영한다
  update ud_responses set group_no = ud_clean(p_group, 3), nickname = v_nick
   where class_code = v_code and client_id = p_client and (group_no, nickname) is distinct from (ud_clean(p_group, 3), v_nick);
  return v_id;
end $$;

-- 게시판에서 내린 질문은 지운다 (질문 칸을 비우고 다시 붙였을 때)
create or replace function public.ud_remove_response(p_code text, p_client uuid, p_mission int, p_item text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from ud_responses where class_code = upper(p_code) and client_id = p_client and mission = p_mission and item = p_item
$$;

-- ───────────── 학생: 질문 게시판 답하기 / 도장 ─────────────
create or replace function public.ud_submit_answer(p_code text, p_client uuid, p_nick text, p_question uuid, p_text text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_code text := upper(p_code); v_text text := ud_clean(p_text, 200);
begin
  if v_text = '' then raise exception 'empty'; end if;
  if not exists (select 1 from ud_responses where id = p_question and class_code = v_code and mission = 4 and item like 'q_') then
    raise exception 'unknown question';
  end if;
  -- 한 질문에 한 사람은 답을 하나만 남긴다(고쳐 쓰면 바뀐다)
  delete from ud_board_answers where class_code = v_code and question_id = p_question and client_id = p_client;
  insert into ud_board_answers (class_code, question_id, client_id, nickname, text)
  values (v_code, p_question, p_client, ud_clean(p_nick, 30), v_text) returning id into v_id;
  return v_id;
end $$;

create or replace function public.ud_toggle_like(p_code text, p_client uuid, p_nick text, p_question uuid)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare v_code text := upper(p_code);
begin
  if not exists (select 1 from ud_responses where id = p_question and class_code = v_code and mission = 4) then
    raise exception 'unknown question';
  end if;
  delete from ud_board_likes where question_id = p_question and client_id = p_client;
  if found then return false; end if;
  insert into ud_board_likes (question_id, class_code, client_id, nickname) values (p_question, v_code, p_client, ud_clean(p_nick, 30));
  return true;
end $$;

-- ───────────── 학생/교사: 학급 집계 ─────────────
-- 학생 개인의 글 원문은 돌려주지 않는다. 질문 게시판(반 전체에 공개하는 활동)만 원문을 담는다.
create or replace function public.ud_class_summary(p_code text, p_client uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_code text := upper(p_code); r jsonb;
begin
  if not ud_class_ok(v_code) then return jsonb_build_object('ok', false); end if;

  with
  people as (
    select distinct on (client_id) client_id, group_no, nickname from ud_responses
     where class_code = v_code order by client_id, updated_at desc),
  prog as (
    select client_id, value from ud_responses where class_code = v_code and mission = 0 and item = 'progress'),
  done as (
    select jsonb_object_agg(m, n) j from (
      select m::text, count(*) filter (where (p.value ->> m::text)::boolean) n
        from generate_series(1, 4) m left join prog p on true group by m) x),
  votes as (
    select jsonb_object_agg(v, n) j from (
      select o v, count(r.client_id) n from unnest(array['양식','출처','내용']) o
        left join ud_responses r on r.class_code = v_code and r.mission = 1 and r.item = 'vote' and r.value ->> 'v' = o
       group by o) x),
  posts as (
    select key pid, (val ->> 'verdict') verdict
      from ud_responses r, jsonb_each(r.value) e(key, val)
     where r.class_code = v_code and r.mission = 2 and r.item = 'posts'),
  trust as (
    select coalesce(jsonb_object_agg(pid, jsonb_build_object('trusted', trusted, 'judged', judged)), '{}') j from (
      select pid, count(*) filter (where verdict = 'true') trusted, count(*) filter (where verdict in ('true','false')) judged
        from posts group by pid) x),
  kwrows as (
    select r.client_id, k.key para, btrim(w) word
      from ud_responses r, jsonb_each_text(r.value) k(key, val), regexp_split_to_table(k.val, '[,،、/\n]+') w
     where r.class_code = v_code and r.mission = 3 and r.item = 'kw' and btrim(w) <> ''),
  kwc as (
    select para, word, count(distinct client_id) n,
           row_number() over (partition by para order by count(distinct client_id) desc, word) rk
      from kwrows group by para, word),
  kw as (
    select coalesce(jsonb_object_agg(para, words), '{}') j from (
      select para, jsonb_object_agg(word, n) words from kwc where rk <= 8 group by para) x),
  qs as (
    select r.id, r.client_id, ud_who(r.group_no, r.nickname) who, r.group_no, r.value, r.updated_at
      from ud_responses r where r.class_code = v_code and r.mission = 4 and r.item like 'q_'),
  board as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id, 'by', q.who, 'kw', q.value ->> 'kw', 't', (q.value ->> 't')::int, 'q', q.value ->> 'text',
      'mine', q.client_id = p_client,
      'likes', (select count(*) from ud_board_likes l where l.question_id = q.id),
      'liked', exists (select 1 from ud_board_likes l where l.question_id = q.id and l.client_id = p_client),
      'ans', coalesce((select jsonb_agg(jsonb_build_object('by', a.nickname, 'text', a.text, 'mine', a.client_id = p_client) order by a.created_at)
                         from ud_board_answers a where a.question_id = q.id), '[]'))
      order by q.updated_at desc), '[]') j from qs q),
  grp as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'group', g.group_no, 'members', g.members, 'solved', g.solved, 'answers', g.answers, 'stamps', g.stamps,
      'score', g.solved * 10 + g.answers * 3 + g.stamps * 2) order by g.solved * 10 + g.answers * 3 + g.stamps * 2 desc, g.group_no), '[]') j
    from (
      select pe.group_no,
             count(*) members,
             coalesce(sum((select count(*) from prog p, jsonb_each_text(p.value) e where p.client_id = pe.client_id and e.key in ('1','2','3','4') and e.value = 'true')), 0) solved,
             coalesce(sum((select count(*) from ud_board_answers a where a.class_code = v_code and a.client_id = pe.client_id)), 0) answers,
             coalesce(sum((select count(*) from ud_board_likes l join qs on qs.id = l.question_id where qs.client_id = pe.client_id)), 0) stamps
        from people pe where pe.group_no <> '' group by pe.group_no) g)
  select jsonb_build_object(
    'ok', true, 'code', v_code, 'name', (select name from ud_classes where code = v_code),
    'participants', (select count(*) from people),
    'done', (select j from done), 'votes', (select j from votes), 'trust', coalesce((select j from trust), '{}'),
    'kw', (select j from kw), 'board', (select j from board), 'groups', (select j from grp),
    'my_answers', (select count(*) from ud_board_answers where class_code = v_code and client_id = p_client),
    'at', now())
  into r;
  return r;
end $$;

-- ───────────── 교사: 원문 보기 ─────────────
create or replace function public.ud_teacher_data(p_code text, p_pin text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_code text := upper(p_code);
begin
  if not exists (select 1 from ud_classes where code = v_code and teacher_pin_hash = crypt(p_pin, teacher_pin_hash)) then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object(
    'ok', true,
    'summary', ud_class_summary(v_code, null),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'client', client_id, 'group', group_no, 'nick', nickname, 'mission', mission, 'item', item,
        'value', value, 'at', updated_at) order by group_no, nickname, mission, item)
      from ud_responses where class_code = v_code), '[]'),
    'answers', coalesce((select jsonb_agg(jsonb_build_object('question', question_id, 'client', client_id, 'nick', nickname, 'text', text, 'at', created_at) order by created_at)
      from ud_board_answers where class_code = v_code), '[]'));
end $$;

-- ───────────── 권한 ─────────────
revoke all on function public.ud_create_class(text, text, text) from public, anon, authenticated;
revoke all on function public.ud_clean(text, int), public.ud_class_ok(text), public.ud_who(text, text) from public, anon, authenticated;
grant execute on function
  public.ud_join_class(text),
  public.ud_submit_response(text, uuid, text, text, int, text, jsonb),
  public.ud_remove_response(text, uuid, int, text),
  public.ud_submit_answer(text, uuid, text, uuid, text),
  public.ud_toggle_like(text, uuid, text, uuid),
  public.ud_class_summary(text, uuid),
  public.ud_teacher_data(text, text)
to anon, authenticated;
