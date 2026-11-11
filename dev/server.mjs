// 로컬 개발 서버: Supabase 프로젝트 없이 "연결 모드"를 시험한다.  실행: npm run dev  → http://localhost:5173
//  * index.html 을 그대로 내보내고, config.js 는 이 서버(가짜 Supabase)를 가리키게 만들어 준다.
//  * /rest/v1/rpc/<함수> 요청을 PGlite 위의 supabase/schema.sql 함수로 처리한다(익명 역할).
//  * 실시간 구독은 흉내 내지 않는다. 앱은 실시간이 없으면 주기적으로 다시 불러온다.
//  * 시험용 학급: 코드 DEMO-5, 교사 PIN 1234
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb, rpc } from './db.mjs';

const PORT = Number(process.env.PORT || 5173);
const ROOT = fileURLToPath(new URL('..', import.meta.url));
const db = await openDb();
await db.query(`select ud_create_class('DEMO-5','5학년 시험 반','1234')`);

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png' };
const send = (res, code, body, type = 'application/json') => { res.writeHead(code, { 'content-type': type, 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' }); res.end(body) };

http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  try {
    if (req.method === 'OPTIONS') return send(res, 204, '');
    const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
    if (m && req.method === 'POST') {
      let body = ''; for await (const c of req) body += c;
      try {
        const out = await rpc(db, m[1], body ? JSON.parse(body) : {});
        return out == null ? send(res, 204, '') : send(res, 200, JSON.stringify(out));
      } catch (e) {
        return send(res, 400, JSON.stringify({ message: e.message, code: 'P0001' }));
      }
    }
    if (url.pathname === '/config.js') {
      return send(res, 200, `window.APP_CONFIG=${JSON.stringify({ supabaseUrl: `http://localhost:${PORT}`, supabaseAnonKey: 'dev-anon-key', realtime: false, pollMs: 4000 })};`, TYPES['.js']);
    }
    let p = url.pathname === '/' ? '/index.html' : url.pathname;
    const file = normalize(join(ROOT, p));
    if (!file.startsWith(ROOT) || /[\\/](node_modules|dev|supabase|\.git)[\\/]/.test(file.slice(ROOT.length - 1))) return send(res, 404, 'not found', 'text/plain');
    return send(res, 200, await readFile(file), TYPES[extname(file)] || 'application/octet-stream');
  } catch (e) {
    return send(res, 404, 'not found', 'text/plain');
  }
}).listen(PORT, () => console.log(`정보 탐정단 개발 서버: http://localhost:${PORT}  (학급 코드 DEMO-5, 교사 PIN 1234)`));
