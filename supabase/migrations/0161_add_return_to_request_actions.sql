-- 0161: Add 'return' to request_actions.action CHECK constraint
-- Needed by decide_request(uuid,'return',text) — V17 §4.2

begin;

alter table public.request_actions drop constraint request_actions_action_check;

alter table public.request_actions add constraint request_actions_action_check
  check (action in (
    'submit','approve','reject','request_changes','comment',
    'escalate','reassign','cancel','withdraw','expire','system',
    'return'
  ));

commit;
