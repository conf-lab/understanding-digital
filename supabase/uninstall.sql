-- 정보 탐정단 앱만 지우기. ud_ 로 시작하는 것만 지우고 같은 프로젝트의 다른 앱(mg_, calc_ 등)은 건드리지 않는다.
-- ⚠️ 학급, 학생 응답, 게시판 답, 도장이 모두 영구히 지워진다. 필요하면 먼저 교사 화면에서 CSV 를 내려받는다.

drop function if exists public.ud_teacher_data(text, text);
drop function if exists public.ud_class_summary(text, uuid);
drop function if exists public.ud_toggle_like(text, uuid, text, uuid);
drop function if exists public.ud_submit_answer(text, uuid, text, uuid, text);
drop function if exists public.ud_remove_response(text, uuid, int, text);
drop function if exists public.ud_submit_response(text, uuid, text, text, int, text, jsonb);
drop function if exists public.ud_join_class(text);
drop function if exists public.ud_create_class(text, text, text);
drop function if exists public.ud_who(text, text);
drop function if exists public.ud_class_ok(text);
drop function if exists public.ud_clean(text, int);

drop table if exists public.ud_board_likes;
drop table if exists public.ud_board_answers;
drop table if exists public.ud_responses;
drop table if exists public.ud_classes;
