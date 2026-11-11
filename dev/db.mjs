// 로컬 개발용: PGlite(웹어셈블리 Postgres)에 supabase/schema.sql 을 그대로 올린다.
// Supabase 의 anon 역할을 흉내 내어, 앱이 쓰는 RPC 가 익명 권한으로 동작하는지 함께 확인한다.
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFile } from 'node:fs/promises';

export async function openDb() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`do $$ begin
    if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  end $$; grant usage on schema public to anon, authenticated;
    -- Supabase 처럼 pgcrypto 를 extensions 스키마에 둔다(search_path 실수를 잡기 위해)
    create schema if not exists extensions; create extension if not exists pgcrypto schema extensions;`);
  const sql = await readFile(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
  await db.exec(sql);
  return db;
}

// PostgREST 의 /rest/v1/rpc/<fn> 처럼 이름 붙은 인자로 함수를 부른다. 항상 anon 역할로 실행.
export async function rpc(db, fn, args, role = 'anon') {
  if (!/^[a-z_]+$/.test(fn)) throw new Error('bad fn');
  const keys = Object.keys(args || {});
  keys.forEach(k => { if (!/^p_[a-z]+$/.test(k)) throw new Error('bad arg ' + k); });
  const call = `select public.${fn}(${keys.map((k, i) => `${k} => $${i + 1}`).join(', ')}) as r`;
  const vals = keys.map(k => (args[k] !== null && typeof args[k] === 'object') ? JSON.stringify(args[k]) : args[k]);
  return db.transaction(async tx => {
    await tx.exec(`set local role ${role}`);
    const res = await tx.query(call, vals);
    return res.rows[0].r;
  });
}
