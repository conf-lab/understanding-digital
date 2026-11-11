# Supabase 연결 방법 (다른 앱과 한 프로젝트를 함께 쓰는 경우)

이 앱은 **이미 다른 앱(`mg_`, `calc_`, `history_` 등)이 쓰고 있는 Supabase 무료 프로젝트에 같이 들어가도록** 만들었습니다.

- 이 앱이 만드는 테이블과 함수는 모두 **`ud_`** 로 시작합니다(understanding-digital).
- 설치 SQL은 `ud_` 로 시작하는 것만 만들거나 바꿉니다. 다른 앱의 테이블, 함수, 데이터는 건드리지 않습니다.
- 새 프로젝트를 만들 필요가 없습니다. 지금 프로젝트의 **URL과 anon 키를 그대로** 씁니다.

연결 전까지 앱은 "연습 모드"(이 기기에만 저장, 반 결과는 예시 데이터)로 동작합니다.

---

## 0단계. 설치 전 확인: `ud_` 이름이 비어 있는지

1. Supabase 대시보드에서 지금 쓰는 프로젝트를 엽니다.
2. 왼쪽 메뉴 **SQL Editor** → **New query**를 누릅니다.
3. 아래를 붙여 넣고 **Run**을 누릅니다.

```sql
select 'table' as kind, table_name as name from information_schema.tables
 where table_schema = 'public' and table_name like 'ud\_%'
union all
select 'function', proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname like 'ud\_%';
```

- **결과가 0줄**(No rows returned)이면 다음 단계로 갑니다.
- 무언가 나오면, 그 이름을 다른 앱이 쓰고 있는지 먼저 확인하세요. 잘 모르겠으면 멈추고 물어보세요.

## 1단계. 테이블과 함수 설치

1. SQL Editor에서 **New query**를 하나 더 엽니다.
2. 깃허브 저장소의 [`supabase/schema.sql`](supabase/schema.sql) 파일을 엽니다. 깃허브에서 **Raw** 버튼을 누르면 복사하기 쉽습니다.
3. 내용 **전부**를 복사해 붙여 넣고 **Run**을 누릅니다.
4. `Success. No rows returned`가 나오면 성공입니다.
   - 여러 번 실행해도 안전합니다. 나중에 `schema.sql`이 바뀌면 같은 방법으로 다시 Run 하면 됩니다.
   - "potential issue" 같은 확인 창이 뜨면 **Run this query**를 누르세요(테이블을 만드는 SQL이라 뜨는 확인입니다).

### 설치 확인
0단계 SQL을 다시 Run 합니다. **15줄**이 나와야 합니다.

| 종류 | 이름 |
|---|---|
| 테이블 4개 | `ud_classes`, `ud_responses`, `ud_board_answers`, `ud_board_likes` |
| 함수 11개 | `ud_create_class`, `ud_join_class`, `ud_submit_response`, `ud_remove_response`, `ud_submit_answer`, `ud_toggle_like`, `ud_class_summary`, `ud_teacher_data`, `ud_clean`, `ud_class_ok`, `ud_who` |

왼쪽 **Table Editor** 목록에도 `ud_` 테이블 4개가 새로 보입니다. 이 테이블들은 **RLS가 켜져 있고 정책이 없는 것이 정상**입니다. 학생 앱은 테이블을 직접 읽지 않고 위 함수로만 접근하기 때문입니다. 그러니 Supabase가 "RLS enabled, no policies"라고 알려도 정책을 추가하지 마세요.

## 2단계. 학급 만들기

SQL Editor에서 반마다 한 번 실행합니다.

```sql
select ud_create_class('5-3-KIM', '5학년 3반', '2580');
```

| 값 | 뜻 | 규칙 |
|---|---|---|
| `5-3-KIM` | **학급 코드**. 학생에게 알려 주는 값입니다(QR에도 들어감) | 영문·숫자·`-`, 3~20자. 대소문자 구분 없음. 남이 짐작하기 어렵게 |
| `5학년 3반` | 화면에 보이는 반 이름 | 자유 |
| `2580` | **선생님 PIN**. 선생님 화면에 들어갈 때만 씁니다 | 4자리 이상. 암호화되어 저장됨 |

- 결과로 `5-3-KIM`이 한 줄 나오면 성공입니다.
- 같은 코드로 다시 실행하면 반 이름과 PIN이 바뀝니다(학생 기록은 그대로).
- 만든 학급 목록 보기: `select code, name, created_at from ud_classes;`

## 3단계. URL과 키 확인 (다른 앱과 같은 값)

다른 앱에서 이미 쓰고 있는 값과 **같은 값**입니다. 그 앱의 설정(예: Vercel 환경 변수)에서 가져와도 되고, 대시보드에서 확인해도 됩니다.

1. 왼쪽 아래 톱니바퀴 **Project Settings**를 누릅니다.
2. **Data API**(또는 API)에서 **Project URL**을 복사합니다. 예: `https://abcd1234.supabase.co`
3. **API Keys**에서 **anon public** 키(`eyJ...`) 또는 **publishable** 키(`sb_publishable_...`)를 복사합니다.

> ⚠️ **`service_role` 키나 `sb_secret_...` 키는 절대 넣지 마세요.** 이 키는 RLS를 무시하므로 다른 앱 데이터까지 모두 열립니다.
> 빌드 스크립트는 이런 키를 발견하면 빌드를 멈춥니다. anon/publishable 키는 브라우저에 공개되어도 괜찮은 키입니다.

## 4단계. Vercel에 넣기

Vercel 프로젝트(understanding-digital) → **Settings → Environment Variables**에 두 개를 넣습니다. 이름을 정확히 이렇게 써야 합니다.

| Key | Value |
|---|---|
| `SUPABASE_URL` | 3단계의 Project URL |
| `SUPABASE_ANON_KEY` | 3단계의 anon 또는 publishable 키 |

- Environment는 **Production, Preview, Development** 모두 체크하면 됩니다.
- **이미 배포했다면** 환경 변수를 넣은 뒤 **Deployments → 맨 위 배포 ⋯ → Redeploy**를 눌러야 반영됩니다. 환경 변수는 빌드할 때 `config.js`로 들어가기 때문입니다.
- 빌드 설정(`npm run build`, 출력 폴더 `dist`)은 `vercel.json`에 이미 있습니다. Framework Preset은 **Other**로 두세요.

### (선택) 내 컴퓨터에서만 시험할 때
저장소 최상위에 `config.js`를 만듭니다. `.gitignore`에 들어 있어 깃허브에 올라가지 않습니다.

```js
window.APP_CONFIG = { supabaseUrl: 'https://abcd1234.supabase.co', supabaseAnonKey: '여기에 anon 키' };
```

```bash
npx http-server@14.1.1 . -p 5174 -c-1
```

## 5단계. 실시간 확인

- 학생이 저장하면 Realtime Broadcast 채널 `ud-class-학급코드`로 신호를 보내고, 교사 화면이 바로 다시 불러옵니다. 채널 이름도 `ud-`로 시작하므로 다른 앱과 섞이지 않습니다.
- 따로 설정할 것은 보통 없습니다. **Project Settings → Realtime**에 "Allow public access"(공개 채널 허용) 같은 설정이 꺼져 있으면 켜 주세요.
  다른 앱이 비공개 채널만 쓰도록 이 설정을 꺼 둔 상태라면, 켜지 않아도 됩니다. 이 앱은 실시간이 안 되어도 15초마다 다시 불러오기 때문입니다.

## 6단계. 연결 확인 (수업 전에 꼭)

1. 선생님 기기에서 배포 주소 뒤에 `#teacher`를 붙여 엽니다 → 학급 코드와 PIN을 넣고 **우리 반 불러오기**를 누릅니다. 학생 입장 QR이 보이면 성공입니다.
2. 휴대폰으로 그 QR을 찍습니다 → 모둠·별명을 쓰고 **입장하기**를 누릅니다. 위쪽 상태 딱지가 **저장됨**이 되면 서버에 저장된 것입니다.
3. 휴대폰에서 1차시 투표를 합니다 → 몇 초 안에 교사 화면 막대가 바뀌면 실시간까지 성공입니다.
4. 교사 화면 **CSV 내려받기** → 엑셀에서 한글이 깨지지 않으면 끝입니다.
5. 시험한 기록 지우기(학급은 남기고 응답만 삭제):

```sql
delete from ud_responses where class_code = '5-3-KIM';
```

## 무료 요금제에서 알아 둘 것

- **용량**: 이 앱은 한 반 4차시를 다 해도 데이터가 아주 작습니다(수백 KB 수준). 다른 앱과 함께 써도 무료 한도(DB 500MB)에 거의 영향이 없습니다.
- **일시 정지**: 무료 프로젝트는 한동안(약 1주) 아무도 쓰지 않으면 멈춥니다. 다른 앱이 꾸준히 쓰면 괜찮지만, 방학 뒤 첫 수업 전날에는 대시보드에서 프로젝트가 **Active**인지 확인하고, 멈춰 있으면 **Restore**를 누르세요. 다시 켜지는 데 몇 분 걸립니다.
- **백업**: 무료 요금제는 자동 백업을 내려받을 수 없습니다. 사례 발표 자료는 수업이 끝날 때마다 교사 화면에서 **CSV 내려받기**로 따로 남겨 두세요.

## 정리하기

- 한 반만 지우기(그 반의 응답·답·도장도 함께 지워짐): `delete from ud_classes where code = '5-3-KIM';`
- 이 앱 전체를 지우기: [`supabase/uninstall.sql`](supabase/uninstall.sql)을 Run 합니다. `ud_`로 시작하는 것만 지우고 다른 앱은 그대로 둡니다.

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| 학생 화면에 「그런 학급 코드가 없어요」 | 2단계를 했는지, 코드 철자(`select code from ud_classes;`) |
| 위쪽에 「연결이 끊겼어요」 | Vercel 환경 변수 이름·값 오타, 넣은 뒤 Redeploy 했는지, 1단계 설치 여부 |
| `function ud_... does not exist` | 1단계 `schema.sql`을 끝까지 Run 했는지 |
| `permission denied for function ...` | 1단계를 다시 Run(맨 아래 grant 부분이 실행되어야 함) |
| `function gen_salt(unknown) does not exist` | 예전 schema.sql입니다. 최신 파일로 1단계를 다시 Run |
| 교사 화면이 자동으로 안 바뀜 | 5단계 Realtime 설정. 「지금 새로 고침」 버튼과 15초 자동 갱신은 항상 동작 |
| 브라우저 개발자 도구에서 원인 보기 | F12 → Network 탭 → `rpc/ud_...` 요청의 응답 내용 |

## (개발자용) Supabase 없이 로컬에서 시험하기

`schema.sql`을 웹어셈블리 Postgres(PGlite)에 그대로 올려 Supabase를 흉내 냅니다. Supabase처럼 `pgcrypto`를 `extensions` 스키마에 둡니다.

```bash
npm install
```

```bash
npm run test:sql
```

```bash
npm run dev
```

`npm run dev`를 실행한 뒤 <http://localhost:5173/?class=DEMO-5>를 엽니다(교사 PIN `1234`). 실시간은 흉내 내지 않고 4초마다 다시 불러옵니다.
