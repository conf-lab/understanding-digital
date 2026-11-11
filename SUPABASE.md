# Supabase 연결 방법

코드는 이미 Supabase를 쓸 수 있게 만들어 두었습니다. 아래 순서대로 **Supabase 프로젝트를 만들고, SQL 한 번 실행하고, 주소와 키 두 개를 넣으면** 연결이 끝납니다.
연결 전까지 앱은 지금처럼 "연습 모드"(이 기기에만 저장, 반 결과는 예시 데이터)로 동작합니다.

---

## 1. Supabase 프로젝트 만들기

1. <https://supabase.com> 에 로그인하고 **New project**를 누릅니다.
2. 이름(예: `info-detective`), 데이터베이스 비밀번호, 지역(**Northeast Asia (Seoul)** 추천)을 정하고 만듭니다. 1~2분 걸립니다.

## 2. 테이블과 함수 만들기 (SQL 한 번 실행)

1. 왼쪽 메뉴 **SQL Editor** → **New query**.
2. 저장소의 [`supabase/schema.sql`](supabase/schema.sql) 내용을 **전부** 복사해 붙여 넣고 **Run**.
   - 오류 없이 `Success. No rows returned` 가 나오면 됩니다.
   - 여러 번 실행해도 안전합니다(나중에 schema.sql 이 바뀌면 다시 Run).

이 SQL이 만드는 것:

| 이름 | 하는 일 |
|---|---|
| `classes` | 학급 코드, 반 이름, 선생님 PIN(암호화해서 저장) |
| `responses` | 학생 응답. `(class_code, group_no, nickname, mission, item, value jsonb)` + 기기 구분용 `client_id` |
| `board_answers` | 질문 게시판 답 |
| `board_likes` | 좋은 질문 도장 |
| `submit_response`, `remove_response` | 학생 응답 저장/지우기 |
| `submit_answer`, `toggle_like` | 게시판 답하기, 도장 찍기 |
| `join_class` | 학급 코드가 있는지 확인 |
| `class_summary` | 학급 **집계**(투표 수, 판정 수, 핵심 낱말 수, 게시판, 모둠 점수) |
| `teacher_data` | 학급 코드 + PIN 이 맞으면 학생 글 원문까지 돌려줌(교사 화면, CSV) |
| `create_class` | 학급 만들기(SQL Editor 에서만 실행 가능) |

**보안(RLS)**: 네 테이블 모두 RLS 가 켜져 있고 익명 사용자용 정책이 없습니다. 즉 익명 키로는 테이블을 직접 읽거나 쓸 수 없고, 위 함수로만
"자기 학급 코드로 쓰기"와 "자기 학급의 집계 읽기"를 할 수 있습니다. 다른 학생의 글 원문(다짐, 까닭 등)은 학생에게 내려가지 않고, PIN 을 아는 교사만 봅니다.
(질문 게시판 질문과 답은 반 전체에 공개하는 활동이므로 집계에 원문이 포함됩니다.)

## 3. 학급 만들기

SQL Editor 에서 반마다 한 번 실행합니다. 코드는 영문·숫자·`-` 3~20자, PIN 은 4자리 이상.

```sql
select create_class('5-3', '5학년 3반', '2580');
```

- 학급 코드(`5-3`)는 학생에게 알려 주는 값입니다. 짐작하기 어렵게 `5-3-KIM` 처럼 만들어도 좋습니다.
- PIN(`2580`)은 선생님 화면에 들어갈 때만 씁니다. 같은 코드로 다시 실행하면 이름과 PIN 이 바뀝니다.
- 수업이 끝난 뒤 학급 자료를 지우려면: `delete from classes where code = '5-3';` (응답·답·도장이 함께 지워짐)

## 4. 주소와 키 확인

**Project Settings → API**(또는 **Data API / API Keys**)에서 두 값을 복사합니다.

| 값 | 어디에 쓰나 |
|---|---|
| **Project URL** (예: `https://abcd1234.supabase.co`) | `SUPABASE_URL` |
| **anon public** 키 (`eyJ...`) 또는 **publishable** 키 (`sb_publishable_...`) | `SUPABASE_ANON_KEY` |

> ⚠️ `service_role` 키나 `sb_secret_...` 키는 **절대** 넣지 마세요. 빌드 스크립트가 이런 키를 발견하면 빌드를 멈춥니다.
> anon/publishable 키는 브라우저에 공개되어도 되는 키입니다. 위의 RLS 와 함수 권한이 데이터를 지킵니다.

## 5. 앱에 연결하기

### 내 컴퓨터에서 시험할 때

저장소 최상위에 `config.js` 파일을 만듭니다(이 파일은 `.gitignore` 에 들어 있어 깃허브에 올라가지 않습니다).

```js
window.APP_CONFIG = {
  supabaseUrl: 'https://abcd1234.supabase.co',
  supabaseAnonKey: '여기에 anon 또는 publishable 키'
};
```

그리고 아무 정적 서버로 엽니다(파일을 더블클릭해 `file://` 로 열면 QR·복사 기능이 제한될 수 있습니다).

```bash
npx http-server@14.1.1 . -p 5174 -c-1
```

### Vercel 에 배포할 때 (배포는 따로 진행)

Vercel 프로젝트 **Settings → Environment Variables** 에 두 값을 넣습니다.

```
SUPABASE_URL       = https://abcd1234.supabase.co
SUPABASE_ANON_KEY  = (anon 또는 publishable 키)
```

`vercel.json` 이 빌드 명령(`npm run build`)과 출력 폴더(`dist`)를 이미 정해 두었습니다. 빌드 때 [`scripts/build.mjs`](scripts/build.mjs) 가 환경 변수로 `dist/config.js` 를 만듭니다.
환경 변수가 없으면 연습 모드로 빌드됩니다.

## 6. 실시간(교사 화면 자동 갱신)

- 학생이 저장하면 같은 학급의 Realtime **Broadcast** 채널(`class-학급코드`)로 "바뀜" 신호를 보내고, 교사 화면과 다른 학생 화면이 집계를 다시 불러옵니다.
- Supabase 새 프로젝트는 Realtime 이 기본으로 켜져 있어 따로 설정할 것이 없습니다. (**Project Settings → Realtime** 에서 "Allow public access"/공개 채널이 꺼져 있다면 켜 주세요.)
- 실시간이 막혀도 앱이 15초마다 다시 불러오므로 수업은 진행됩니다.

## 7. 연결 확인 순서

1. 선생님 기기에서 `#teacher` → 학급 코드와 PIN 입력 → "우리 반 불러오기". 학생 입장 QR이 보이면 성공.
2. 학생 기기로 QR을 찍거나 `https://(주소)/?class=5-3` 로 들어가 모둠·별명을 쓰고 **입장하기**.
   머리의 상태 딱지가 「저장됨」으로 바뀌면 서버에 저장된 것입니다.
3. 학생이 1차시 투표를 하면 몇 초 안에 교사 화면의 막대가 바뀝니다.
4. 교사 화면에서 **CSV 내려받기** → 엑셀에서 한글이 깨지지 않고 열리면 끝.

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| 학생 화면에 「그런 학급 코드가 없어요」 | 3단계 `create_class` 를 실행했는지, 코드 철자 |
| 머리에 「연결이 끊겼어요」 | `SUPABASE_URL`/키 오타, 2단계 SQL 실행 여부. 브라우저 개발자 도구 Network 탭에서 `/rest/v1/rpc/...` 응답을 확인 |
| `permission denied for function ...` | 2단계 SQL 을 다시 Run(맨 아래 grant 부분이 실행되어야 함) |
| 교사 화면이 자동으로 안 바뀜 | 6단계 Realtime 설정. 「지금 새로 고침」 버튼으로도 갱신됨 |
| Supabase 무료 프로젝트가 일시 정지됨 | 무료 요금제는 오래 쓰지 않으면 멈춥니다. 수업 전날 대시보드에서 **Restore** |

## 로컬에서 Supabase 없이 연결 모드 시험하기

Supabase 프로젝트를 만들기 전에도 연결 모드를 시험할 수 있습니다. `schema.sql` 을 웹어셈블리 Postgres(PGlite)에 그대로 올려 Supabase RPC 를 흉내 냅니다.

```bash
npm install
```

```bash
npm run test:sql
```

```bash
npm run dev
```

`npm run dev` 후 <http://localhost:5173/?class=DEMO-5> (교사 PIN `1234`). 이 개발 서버는 실시간 신호는 흉내 내지 않고 4초마다 다시 불러옵니다. 서버를 끄면 데이터는 사라집니다.
