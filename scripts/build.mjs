// 배포용 빌드: index.html 을 dist/ 에 복사하고, 환경 변수로 dist/config.js 를 만든다.
//   SUPABASE_URL       예) https://abcd1234.supabase.co
//   SUPABASE_ANON_KEY  Supabase 의 anon(공개) 키 또는 publishable 키. service_role 키는 절대 넣지 않는다.
// 두 값이 없으면 config.js 없이 빌드되어 "연습 모드"로 동작한다.
import { mkdir, copyFile, writeFile, rm } from 'node:fs/promises';

const url = (process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '').trim();
const key = (process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '').trim();

if (/^sb_secret_/.test(key) || /service_role/.test(Buffer.from((key.split('.')[1] || ''), 'base64').toString())) {
  console.error('SUPABASE_ANON_KEY 에 비밀(service_role/secret) 키가 들어 있습니다. 공개용 anon 또는 publishable 키를 넣어 주세요.');
  process.exit(1);
}
if (url && !/^https:\/\/[^\s/]+$/.test(url.replace(/\/+$/, ''))) {
  console.error('SUPABASE_URL 형식이 이상합니다: https://프로젝트.supabase.co 형태여야 합니다.');
  process.exit(1);
}

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });
await copyFile('index.html', 'dist/index.html');
if (url && key) {
  await writeFile('dist/config.js', `window.APP_CONFIG=${JSON.stringify({ supabaseUrl: url.replace(/\/+$/, ''), supabaseAnonKey: key })};\n`);
  console.log('연결 모드로 빌드했습니다:', url);
} else {
  await writeFile('dist/config.js', '/* Supabase 환경 변수가 없어 연습 모드로 빌드했습니다. */\n');
  console.log('SUPABASE_URL / SUPABASE_ANON_KEY 가 없어 연습 모드로 빌드했습니다.');
}
