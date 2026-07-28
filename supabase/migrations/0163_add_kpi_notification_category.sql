-- 0162: Add 'kpi' to notifications.category CHECK constraint
-- Required by advance_kpi_stage / return_kpi_stage (mig 0146) which inserts
-- notifications with category='kpi' for stage-transition alerts.

begin;

alter table public.notifications drop constraint notifications_category_check;

alter table public.notifications add constraint notifications_category_check
  check (category in (
    'general','decision','announcement','survey','request',
    'dispute','recognition','system','kpi'
  ));

commit;
