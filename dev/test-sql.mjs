// supabase/schema.sql 을 PGlite 에 올려 RPC 와 권한을 확인한다.  실행: npm run test:sql
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { openDb, rpc } from './db.mjs';

const db = await openDb();
await db.query(`select create_class('TEST-1','5학년 1반','1234')`);
// 여러 번 실행해도 안전한지
const { readFile } = await import('node:fs/promises');
await db.exec(await readFile(new URL('../supabase/schema.sql', import.meta.url), 'utf8'));

const C = 'test-1';
const a = randomUUID(), b = randomUUID(), c = randomUUID();
const put = (cl, g, n, m, item, value) => rpc(db, 'submit_response', { p_code: C, p_client: cl, p_group: g, p_nick: n, p_mission: m, p_item: item, p_value: value });

assert.deepEqual((await rpc(db, 'join_class', { p_code: C })).ok, true);
assert.deepEqual((await rpc(db, 'join_class', { p_code: 'nope' })).ok, false);

await put(a, '1', '하늘', 1, 'vote', { v: '출처', reason: '누가 썼는지' });
await put(b, '1', '서연', 1, 'vote', { v: '출처' });
await put(c, '2', '민준', 1, 'vote', { v: '양식' });
await put(a, '1', '하늘', 2, 'posts', { p1: { verdict: true }, p2: { verdict: false } });
await put(b, '1', '서연', 2, 'posts', { p1: { verdict: false } });
await put(a, '1', '하늘', 3, 'kw', { 1: '지구 온난화, 벼', 2: '광합성' });
await put(b, '1', '서연', 3, 'kw', { 1: '벼/쌀', 2: '' });
await put(a, '1', '하늘', 0, 'progress', { 1: true, 2: true, 3: false, 4: false });
await put(c, '2', '민준', 0, 'progress', { 1: true });
const q1 = await put(a, '1', '하늘', 4, 'q1', { kw: '벼', t: 1, text: '벼는 어떤 환경에서 잘 자랄까?' });
// 같은 항목을 다시 보내면 id 가 유지된다
assert.equal(await put(a, '1', '하늘', 4, 'q1', { kw: '벼', t: 1, text: '벼는 어떤 환경에서 잘 자랄까?!' }), q1);

await rpc(db, 'submit_answer', { p_code: C, p_client: c, p_nick: '2모둠 민준', p_question: q1, p_text: '따뜻하고 물이 많은 곳' });
await rpc(db, 'submit_answer', { p_code: C, p_client: c, p_nick: '2모둠 민준', p_question: q1, p_text: '고친 답' });
assert.equal(await rpc(db, 'toggle_like', { p_code: C, p_client: b, p_nick: '1모둠 서연', p_question: q1 }), true);
assert.equal(await rpc(db, 'toggle_like', { p_code: C, p_client: c, p_nick: '2모둠 민준', p_question: q1 }), true);
assert.equal(await rpc(db, 'toggle_like', { p_code: C, p_client: c, p_nick: '2모둠 민준', p_question: q1 }), false);

const s = await rpc(db, 'class_summary', { p_code: C, p_client: b });
assert.equal(s.ok, true);
assert.equal(s.participants, 3);
assert.deepEqual(s.votes, { 양식: 1, 출처: 2, 내용: 0 });
assert.deepEqual(s.trust.p1, { trusted: 1, judged: 2 });
assert.deepEqual(s.trust.p2, { trusted: 0, judged: 1 });
assert.equal(s.kw['1']['벼'], 2);
assert.equal(s.kw['1']['쌀'], 1);
assert.deepEqual(s.done, { 1: 2, 2: 1, 3: 0, 4: 0 });
assert.equal(s.board.length, 1);
assert.equal(s.board[0].q, '벼는 어떤 환경에서 잘 자랄까?!');
assert.equal(s.board[0].by, '1모둠 하늘');
assert.equal(s.board[0].likes, 1);
assert.equal(s.board[0].liked, true);
assert.equal(s.board[0].mine, false);
assert.equal(s.board[0].ans.length, 1);
assert.equal(s.board[0].ans[0].text, '고친 답');
const g1 = s.groups.find(g => g.group === '1'), g2 = s.groups.find(g => g.group === '2');
assert.deepEqual([g1.members, g1.solved, g1.stamps, g1.answers], [2, 2, 1, 0]);
assert.deepEqual([g2.members, g2.solved, g2.answers], [1, 1, 1]);
assert.equal(JSON.stringify(s).includes('누가 썼는지'), false, '집계에 학생 글 원문이 들어가면 안 된다');

// 별명을 바꾸면 기존 응답에도 반영
await put(a, '3', '하늘이', 1, 'vote', { v: '내용' });
const s2 = await rpc(db, 'class_summary', { p_code: C, p_client: a });
assert.equal(s2.board[0].by, '3모둠 하늘이');
assert.equal(s2.board[0].mine, true);

// 교사 원문
assert.equal((await rpc(db, 'teacher_data', { p_code: C, p_pin: '0000' })).ok, false);
const t = await rpc(db, 'teacher_data', { p_code: C, p_pin: '1234' });
assert.equal(t.ok, true);
assert.ok(t.rows.length >= 8);
assert.equal(t.answers.length, 1);

// 거부되어야 하는 것들
const rejects = async (p, re) => { await assert.rejects(p, re) };
await rejects(put(a, '1', '하늘', 1, 'vote', { v: 'x' }).then(() => rpc(db, 'submit_response', { p_code: 'NOPE', p_client: a, p_group: '1', p_nick: '하늘', p_mission: 1, p_item: 'vote', p_value: {} })), /unknown class/);
await rejects(put(a, '1', '', 1, 'vote', {}), /nickname/);
await rejects(put(a, '1', '하늘', 1, 'Bad-Item', {}), /bad item/);
await rejects(put(a, '1', '하늘', 1, 'big', { x: 'ㄱ'.repeat(3000) }), /too large/);
await rejects(rpc(db, 'create_class', { p_code: 'HACK', p_name: '', p_pin: '9999' }), /permission denied/);
for (const tbl of ['classes', 'responses', 'board_answers', 'board_likes']) {
  await rejects(db.transaction(async tx => { await tx.exec('set local role anon'); await tx.query(`select * from ${tbl}`) }), /permission denied/);
}
// 다른 반의 질문에는 답할 수 없다
await db.query(`select create_class('OTHER','다른 반','5555')`);
await rejects(rpc(db, 'submit_answer', { p_code: 'OTHER', p_client: c, p_nick: 'x', p_question: q1, p_text: 'hi' }), /unknown question/);

// 질문 내리기
await rpc(db, 'remove_response', { p_code: C, p_client: a, p_mission: 4, p_item: 'q1' });
assert.equal((await rpc(db, 'class_summary', { p_code: C })).board.length, 0);

console.log('SQL 테스트 모두 통과');
