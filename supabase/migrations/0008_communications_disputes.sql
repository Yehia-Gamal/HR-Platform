-- Migration 0008: القرارات والتواصل والنزاعات (Decisions, Communications & Disputes)
-- يعتمد على: 0002 (دوال التخويل)، 0004 (employees). لا يعيد تعريف أي جدول سابق.
-- تشغيل عبر: supabase db push. الملف idempotent قدر الإمكان.
-- كل الطوابع الزمنية UTC. لا DROP لأي جدول.

-- =====================================================================
-- 0) trigger helper (idempotent — نفس التعريف المستخدم في 0003/0004/0006)
-- =====================================================================
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
comment on function public.tg_set_updated_at() is
  'Trigger helper: sets updated_at = now() (UTC) on row update.';

-- =====================================================================
-- Table: administrative_decisions  (القرارات الإدارية)
-- =====================================================================
create table if not exists public.administrative_decisions (
  id                 uuid primary key default gen_random_uuid(),
  decision_number    text,
  title              text not null,
  body              text,
  category           text not null default 'general'
                       check (category in ('general','hr','financial','disciplinary','organizational','policy')),
  status             text not null default 'draft'
                       check (status in ('draft','published','archived','revoked')),
  target_type        text not null default 'all'
                       check (target_type in ('all','employee','department','branch','role','selected')),
  issued_by          uuid references public.employees(id) on delete set null,
  effective_date     date,
  expiry_date        date,
  requires_read_receipt boolean not null default true,
  attachment_url     text,
  published_at       timestamptz,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.administrative_decisions is
  'القرارات الإدارية الرسمية: العنوان، الفئة، الحالة، نوع الجمهور المستهدف، وتاريخ السريان.';

create unique index if not exists ux_admin_decisions_number
  on public.administrative_decisions (decision_number)
  where decision_number is not null;
create index if not exists ix_admin_decisions_status on public.administrative_decisions (status);
create index if not exists ix_admin_decisions_category on public.administrative_decisions (category);
create index if not exists ix_admin_decisions_effective on public.administrative_decisions (effective_date);

drop trigger if exists trg_admin_decisions_updated_at on public.administrative_decisions;
create trigger trg_admin_decisions_updated_at
  before update on public.administrative_decisions
  for each row execute function public.tg_set_updated_at();

alter table public.administrative_decisions enable row level security;

-- Initial policy. The target-scoped branch is added after
-- decision_recipients is created below.
drop policy if exists admin_decisions_select on public.administrative_decisions;
create policy admin_decisions_select on public.administrative_decisions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
  );

drop policy if exists admin_decisions_write on public.administrative_decisions;
create policy admin_decisions_write on public.administrative_decisions
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.decision.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.decision.manage'));

-- =====================================================================
-- Table: decision_recipients  (مستلمو القرار — تحديد النطاق المستهدف)
-- =====================================================================
create table if not exists public.decision_recipients (
  id                 uuid primary key default gen_random_uuid(),
  decision_id        uuid not null references public.administrative_decisions(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  is_primary         boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  unique (decision_id, employee_id)
);
comment on table public.decision_recipients is
  'ربط القرار بالموظفين المستهدفين — يحدد نطاق قراءة القرار (target-scoped).';

create index if not exists ix_decision_recipients_employee on public.decision_recipients (employee_id);
create index if not exists ix_decision_recipients_decision on public.decision_recipients (decision_id);

alter table public.decision_recipients enable row level security;

drop policy if exists decision_recipients_select on public.decision_recipients;
create policy decision_recipients_select on public.decision_recipients
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
    or employee_id = public.current_employee_id()
  );

drop policy if exists decision_recipients_write on public.decision_recipients;
create policy decision_recipients_write on public.decision_recipients
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.decision.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.decision.manage'));

-- Now that decision_recipients exists, install the complete target-scoped
-- read policy for published decisions.
drop policy admin_decisions_select on public.administrative_decisions;
create policy admin_decisions_select on public.administrative_decisions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
    or (
      status = 'published'
      and exists (
        select 1 from public.decision_recipients dr
        where dr.decision_id = administrative_decisions.id
          and dr.employee_id = public.current_employee_id()
      )
    )
  );

-- =====================================================================
-- Table: decision_reads  (إيصالات قراءة القرار — read receipts)
-- =====================================================================
create table if not exists public.decision_reads (
  id                 uuid primary key default gen_random_uuid(),
  decision_id        uuid not null references public.administrative_decisions(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  read_at            timestamptz not null default now(),
  acknowledged       boolean not null default false,
  acknowledged_at    timestamptz,
  ip_address         inet,
  user_agent         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  unique (decision_id, employee_id)
);
comment on table public.decision_reads is
  'إيصالات قراءة القرارات الإدارية (read receipts) مع الإقرار الاختياري.';

create index if not exists ix_decision_reads_employee on public.decision_reads (employee_id);
create index if not exists ix_decision_reads_decision on public.decision_reads (decision_id);

drop trigger if exists trg_decision_reads_updated_at on public.decision_reads;
create trigger trg_decision_reads_updated_at
  before update on public.decision_reads
  for each row execute function public.tg_set_updated_at();

alter table public.decision_reads enable row level security;

-- الموظف يقرأ/يكتب إيصاله فقط؛ المخوّل يقرأ الكل
drop policy if exists decision_reads_select on public.decision_reads;
create policy decision_reads_select on public.decision_reads
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
    or employee_id = public.current_employee_id()
  );

drop policy if exists decision_reads_insert on public.decision_reads;
create policy decision_reads_insert on public.decision_reads
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

drop policy if exists decision_reads_update on public.decision_reads;
create policy decision_reads_update on public.decision_reads
  for update to authenticated
  using (employee_id = public.current_employee_id())
  with check (employee_id = public.current_employee_id());

-- =====================================================================
-- Table: announcements  (الإعلانات الداخلية)
-- =====================================================================
create table if not exists public.announcements (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  body               text not null,
  category           text not null default 'general'
                       check (category in ('general','event','urgent','policy','celebration','maintenance')),
  priority           text not null default 'normal'
                       check (priority in ('low','normal','high','urgent')),
  status             text not null default 'draft'
                       check (status in ('draft','published','archived')),
  target_type        text not null default 'all'
                       check (target_type in ('all','department','branch','role','selected')),
  requires_acknowledgement boolean not null default false,
  pinned             boolean not null default false,
  banner_url         text,
  published_at       timestamptz,
  expires_at         timestamptz,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.announcements is
  'الإعلانات الداخلية للموظفين: الفئة، الأولوية، الحالة، إمكانية التثبيت وطلب الإقرار.';

create index if not exists ix_announcements_status on public.announcements (status);
create index if not exists ix_announcements_priority on public.announcements (priority);
create index if not exists ix_announcements_pinned on public.announcements (pinned) where pinned = true;

drop trigger if exists trg_announcements_updated_at on public.announcements;
create trigger trg_announcements_updated_at
  before update on public.announcements
  for each row execute function public.tg_set_updated_at();

alter table public.announcements enable row level security;

-- قراءة: كل مصادَق يرى المنشور؛ المخوّل يرى المسودات أيضاً
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements
  for select to authenticated
  using (
    status = 'published'
    or public.current_is_full_access()
    or public.has_any_permission(array['comms.announcement.read','comms.announcement.manage'])
  );

drop policy if exists announcements_write on public.announcements;
create policy announcements_write on public.announcements
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.announcement.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.announcement.manage'));

-- =====================================================================
-- Table: announcement_acknowledgements  (إقرارات الإعلانات)
-- =====================================================================
create table if not exists public.announcement_acknowledgements (
  id                 uuid primary key default gen_random_uuid(),
  announcement_id    uuid not null references public.announcements(id) on delete cascade,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  acknowledged_at    timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  unique (announcement_id, employee_id)
);
comment on table public.announcement_acknowledgements is
  'إقرارات الموظفين باطّلاعهم على الإعلانات التي تتطلب إقراراً.';

create index if not exists ix_ann_ack_employee on public.announcement_acknowledgements (employee_id);
create index if not exists ix_ann_ack_announcement on public.announcement_acknowledgements (announcement_id);

alter table public.announcement_acknowledgements enable row level security;

drop policy if exists ann_ack_select on public.announcement_acknowledgements;
create policy ann_ack_select on public.announcement_acknowledgements
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('comms.announcement.manage')
    or employee_id = public.current_employee_id()
  );

drop policy if exists ann_ack_insert on public.announcement_acknowledgements;
create policy ann_ack_insert on public.announcement_acknowledgements
  for insert to authenticated
  with check (employee_id = public.current_employee_id());

-- =====================================================================
-- Table: surveys  (الاستبيانات)
-- =====================================================================
create table if not exists public.surveys (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  description        text,
  status             text not null default 'draft'
                       check (status in ('draft','open','closed','archived')),
  is_anonymous       boolean not null default true,
  target_type        text not null default 'all'
                       check (target_type in ('all','department','branch','role','selected')),
  starts_at          timestamptz,
  ends_at            timestamptz,
  allow_multiple_responses boolean not null default false,
  published_at       timestamptz,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.surveys is
  'الاستبيانات الداخلية: الحالة، سرية الردود، الجمهور المستهدف ونافذة التوقيت.';

create index if not exists ix_surveys_status on public.surveys (status);

drop trigger if exists trg_surveys_updated_at on public.surveys;
create trigger trg_surveys_updated_at
  before update on public.surveys
  for each row execute function public.tg_set_updated_at();

alter table public.surveys enable row level security;

drop policy if exists surveys_select on public.surveys;
create policy surveys_select on public.surveys
  for select to authenticated
  using (
    status in ('open','closed')
    or public.current_is_full_access()
    or public.has_any_permission(array['comms.survey.read','comms.survey.manage'])
  );

drop policy if exists surveys_write on public.surveys;
create policy surveys_write on public.surveys
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.survey.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.survey.manage'));

-- =====================================================================
-- Table: survey_questions  (أسئلة الاستبيان)
-- =====================================================================
create table if not exists public.survey_questions (
  id                 uuid primary key default gen_random_uuid(),
  survey_id          uuid not null references public.surveys(id) on delete cascade,
  question_text      text not null,
  question_type      text not null default 'single_choice'
                       check (question_type in ('single_choice','multiple_choice','text','rating','scale','yes_no')),
  options            jsonb not null default '[]'::jsonb,
  is_required        boolean not null default true,
  sort_order         integer not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.survey_questions is
  'أسئلة الاستبيان مع نوع السؤال وخياراته وترتيبه.';

create index if not exists ix_survey_questions_survey on public.survey_questions (survey_id, sort_order);

drop trigger if exists trg_survey_questions_updated_at on public.survey_questions;
create trigger trg_survey_questions_updated_at
  before update on public.survey_questions
  for each row execute function public.tg_set_updated_at();

alter table public.survey_questions enable row level security;

drop policy if exists survey_questions_select on public.survey_questions;
create policy survey_questions_select on public.survey_questions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.survey.read','comms.survey.manage'])
    or exists (
      select 1 from public.surveys s
      where s.id = survey_questions.survey_id and s.status in ('open','closed')
    )
  );

drop policy if exists survey_questions_write on public.survey_questions;
create policy survey_questions_write on public.survey_questions
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.survey.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.survey.manage'));

-- =====================================================================
-- Table: survey_responses  (ردود الاستبيان — مجهولة عند الحاجة)
-- =====================================================================
create table if not exists public.survey_responses (
  id                 uuid primary key default gen_random_uuid(),
  survey_id          uuid not null references public.surveys(id) on delete cascade,
  question_id        uuid not null references public.survey_questions(id) on delete cascade,
  -- respondent_hash: بصمة غير قابلة للعكس لمنع الردود المكررة مع حفظ السرية
  respondent_hash    text,
  answer             jsonb not null default '{}'::jsonb,
  answer_text        text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.survey_responses is
  'ردود الاستبيان. للاستبيانات المجهولة لا يُخزَّن معرّف الموظف — فقط بصمة respondent_hash لمنع التكرار.';

create index if not exists ix_survey_responses_survey on public.survey_responses (survey_id);
create index if not exists ix_survey_responses_question on public.survey_responses (question_id);
create index if not exists ix_survey_responses_hash on public.survey_responses (survey_id, respondent_hash)
  where respondent_hash is not null;

alter table public.survey_responses enable row level security;

-- القراءة للمخوّلين فقط (نتائج مجمّعة)؛ الإدراج لأي مصادَق (الردود مجهولة)
drop policy if exists survey_responses_select on public.survey_responses;
create policy survey_responses_select on public.survey_responses
  for select to authenticated
  using (public.current_is_full_access() or public.has_any_permission(array['comms.survey.results','comms.survey.manage']));

drop policy if exists survey_responses_insert on public.survey_responses;
create policy survey_responses_insert on public.survey_responses
  for insert to authenticated
  with check (
    exists (
      select 1 from public.surveys s
      where s.id = survey_responses.survey_id and s.status = 'open'
    )
  );

-- =====================================================================
-- Table: suggestions  (صندوق المقترحات)
-- =====================================================================
create table if not exists public.suggestions (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  body               text not null,
  category           text not null default 'general'
                       check (category in ('general','process','workplace','technology','wellbeing','other')),
  is_anonymous       boolean not null default false,
  submitted_by       uuid references public.employees(id) on delete set null,
  status             text not null default 'submitted'
                       check (status in ('submitted','under_review','accepted','rejected','implemented')),
  review_note        text,
  reviewed_by        uuid references public.employees(id) on delete set null,
  reviewed_at        timestamptz,
  upvotes            integer not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.suggestions is
  'صندوق مقترحات الموظفين: يمكن أن يكون مجهولاً، مع دورة مراجعة وحالة تنفيذ.';

create index if not exists ix_suggestions_status on public.suggestions (status);
create index if not exists ix_suggestions_submitted_by on public.suggestions (submitted_by);

drop trigger if exists trg_suggestions_updated_at on public.suggestions;
create trigger trg_suggestions_updated_at
  before update on public.suggestions
  for each row execute function public.tg_set_updated_at();

alter table public.suggestions enable row level security;

-- الموظف يرى مقترحاته؛ المخوّل يرى الكل
drop policy if exists suggestions_select on public.suggestions;
create policy suggestions_select on public.suggestions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_any_permission(array['comms.suggestion.read','comms.suggestion.manage'])
    or (submitted_by is not null and submitted_by = public.current_employee_id())
  );

drop policy if exists suggestions_insert on public.suggestions;
create policy suggestions_insert on public.suggestions
  for insert to authenticated
  with check (
    -- مقترح مجهول أو منسوب للموظف الحالي
    (is_anonymous = true and submitted_by is null)
    or submitted_by = public.current_employee_id()
  );

drop policy if exists suggestions_update on public.suggestions;
create policy suggestions_update on public.suggestions
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.suggestion.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.suggestion.manage'));

drop policy if exists suggestions_delete on public.suggestions;
create policy suggestions_delete on public.suggestions
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.suggestion.manage'));

-- =====================================================================
-- Table: recognitions  (التقدير والشكر)
-- =====================================================================
create table if not exists public.recognitions (
  id                 uuid primary key default gen_random_uuid(),
  recipient_employee_id uuid not null references public.employees(id) on delete cascade,
  nominated_by       uuid references public.employees(id) on delete set null,
  recognition_type   text not null default 'appreciation'
                       check (recognition_type in ('appreciation','employee_of_month','milestone','team_award','peer_kudos')),
  title              text not null,
  message            text,
  badge              text,
  is_public          boolean not null default true,
  points             integer not null default 0,
  awarded_at         timestamptz not null default now(),
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.recognitions is
  'شهادات التقدير والشكر بين الموظفين والإدارة، عامة أو خاصة، مع نقاط وشارات.';

create index if not exists ix_recognitions_recipient on public.recognitions (recipient_employee_id);
create index if not exists ix_recognitions_nominated_by on public.recognitions (nominated_by);

drop trigger if exists trg_recognitions_updated_at on public.recognitions;
create trigger trg_recognitions_updated_at
  before update on public.recognitions
  for each row execute function public.tg_set_updated_at();

alter table public.recognitions enable row level security;

-- قراءة: العامة للجميع؛ الخاصة للمستلم/المرشِّح/المخوّل
drop policy if exists recognitions_select on public.recognitions;
create policy recognitions_select on public.recognitions
  for select to authenticated
  using (
    is_public = true
    or public.current_is_full_access()
    or public.has_any_permission(array['comms.recognition.read','comms.recognition.manage'])
    or recipient_employee_id = public.current_employee_id()
    or nominated_by = public.current_employee_id()
  );

drop policy if exists recognitions_insert on public.recognitions;
create policy recognitions_insert on public.recognitions
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('comms.recognition.manage')
    or nominated_by = public.current_employee_id()
  );

drop policy if exists recognitions_write on public.recognitions;
create policy recognitions_write on public.recognitions
  for update to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.recognition.manage'))
  with check (public.current_is_full_access() or public.has_permission('comms.recognition.manage'));

-- =====================================================================
-- Table: notifications  (الإشعارات — owner-scoped)
-- =====================================================================
create table if not exists public.notifications (
  id                 uuid primary key default gen_random_uuid(),
  recipient_user_id  uuid not null references auth.users(id) on delete cascade,
  recipient_employee_id uuid references public.employees(id) on delete set null,
  title              text not null,
  body               text,
  category           text not null default 'general'
                       check (category in ('general','decision','announcement','survey','request','dispute','recognition','system')),
  priority           text not null default 'normal'
                       check (priority in ('low','normal','high','urgent')),
  action_url         text,
  entity_type        text,
  entity_id          uuid,
  is_read            boolean not null default false,
  read_at            timestamptz,
  is_archived        boolean not null default false,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.notifications is
  'إشعارات المستخدمين (owner-scoped): كل مستخدم يرى ويحدّث إشعاراته فقط.';

create index if not exists ix_notifications_recipient on public.notifications (recipient_user_id);
create index if not exists ix_notifications_unread on public.notifications (recipient_user_id) where is_read = false;
create index if not exists ix_notifications_category on public.notifications (category);

drop trigger if exists trg_notifications_updated_at on public.notifications;
create trigger trg_notifications_updated_at
  before update on public.notifications
  for each row execute function public.tg_set_updated_at();

alter table public.notifications enable row level security;

-- owner: صاحب الإشعار يقرأ/يحدّث/يحذف؛ المخوّل بإرسال إشعارات النظام يدرج
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated
  using (recipient_user_id = auth.uid() or public.current_is_full_access());

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
  for insert to authenticated
  with check (public.current_is_full_access() or public.has_permission('comms.notification.send'));

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (recipient_user_id = auth.uid())
  with check (recipient_user_id = auth.uid());

drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications
  for delete to authenticated
  using (recipient_user_id = auth.uid());

-- =====================================================================
-- Table: push_subscriptions  (اشتراكات الدفع Web Push — owner-scoped)
-- =====================================================================
create table if not exists public.push_subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  endpoint           text not null,
  p256dh_key         text not null,
  auth_key           text not null,
  user_agent         text,
  device_label       text,
  is_active          boolean not null default true,
  last_used_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id),
  unique (user_id, endpoint)
);
comment on table public.push_subscriptions is
  'اشتراكات Web Push لكل مستخدم/جهاز (owner-scoped) لإرسال الإشعارات الفورية.';

create index if not exists ix_push_subs_user on public.push_subscriptions (user_id);
create index if not exists ix_push_subs_active on public.push_subscriptions (user_id) where is_active = true;

drop trigger if exists trg_push_subs_updated_at on public.push_subscriptions;
create trigger trg_push_subs_updated_at
  before update on public.push_subscriptions
  for each row execute function public.tg_set_updated_at();

alter table public.push_subscriptions enable row level security;

-- owner: كل مستخدم يدير اشتراكاته فقط
drop policy if exists push_subs_select on public.push_subscriptions;
create policy push_subs_select on public.push_subscriptions
  for select to authenticated
  using (user_id = auth.uid() or public.current_is_full_access());

drop policy if exists push_subs_insert on public.push_subscriptions;
create policy push_subs_insert on public.push_subscriptions
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists push_subs_update on public.push_subscriptions;
create policy push_subs_update on public.push_subscriptions
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists push_subs_delete on public.push_subscriptions;
create policy push_subs_delete on public.push_subscriptions
  for delete to authenticated
  using (user_id = auth.uid());

-- =====================================================================
-- Table: notification_delivery_log  (سجل تسليم الإشعارات)
-- =====================================================================
create table if not exists public.notification_delivery_log (
  id                 uuid primary key default gen_random_uuid(),
  notification_id    uuid references public.notifications(id) on delete set null,
  subscription_id    uuid references public.push_subscriptions(id) on delete set null,
  recipient_user_id  uuid references auth.users(id) on delete set null,
  channel            text not null default 'push'
                       check (channel in ('push','email','sms','in_app','webhook')),
  status             text not null default 'queued'
                       check (status in ('queued','sent','delivered','failed','bounced')),
  provider_message_id text,
  error_detail       text,
  attempts           integer not null default 0,
  sent_at            timestamptz,
  delivered_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.notification_delivery_log is
  'سجل محاولات تسليم الإشعارات عبر القنوات المختلفة مع الحالة والأخطاء.';

create index if not exists ix_notif_delivery_notification on public.notification_delivery_log (notification_id);
create index if not exists ix_notif_delivery_user on public.notification_delivery_log (recipient_user_id);
create index if not exists ix_notif_delivery_status on public.notification_delivery_log (status);

drop trigger if exists trg_notif_delivery_updated_at on public.notification_delivery_log;
create trigger trg_notif_delivery_updated_at
  before update on public.notification_delivery_log
  for each row execute function public.tg_set_updated_at();

alter table public.notification_delivery_log enable row level security;

-- المستخدم يرى سجلات تسليمه؛ الكتابة للمخوّل بإدارة النظام
drop policy if exists notif_delivery_select on public.notification_delivery_log;
create policy notif_delivery_select on public.notification_delivery_log
  for select to authenticated
  using (recipient_user_id = auth.uid() or public.current_is_full_access() or public.has_permission('comms.notification.admin'));

drop policy if exists notif_delivery_write on public.notification_delivery_log;
create policy notif_delivery_write on public.notification_delivery_log
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('comms.notification.admin'))
  with check (public.current_is_full_access() or public.has_permission('comms.notification.admin'));

-- =====================================================================
-- Table: dispute_cases  (قضايا النزاعات)
-- =====================================================================
create table if not exists public.dispute_cases (
  id                 uuid primary key default gen_random_uuid(),
  case_number        text,
  title              text not null,
  description        text,
  case_type          text not null default 'grievance'
                       check (case_type in ('grievance','disciplinary','harassment','conflict','misconduct','other')),
  status             text not null default 'open'
                       check (status in ('open','under_investigation','in_hearing','resolved','closed','escalated','dismissed')),
  severity           text not null default 'medium'
                       check (severity in ('low','medium','high','critical')),
  -- actor: الموظف مقدّم الشكوى / الطرف الفاعل
  actor_employee_id  uuid references public.employees(id) on delete set null,
  -- respondent: الطرف المشتكى عليه
  respondent_employee_id uuid references public.employees(id) on delete set null,
  assigned_to        uuid references public.employees(id) on delete set null,
  is_confidential    boolean not null default true,
  opened_at          timestamptz not null default now(),
  resolved_at        timestamptz,
  resolution_summary text,
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.dispute_cases is
  'قضايا النزاعات والشكاوى: النوع، الحالة، الخطورة، الطرف الفاعل والمشتكى عليه والمحقّق المكلّف.';

create unique index if not exists ux_dispute_cases_number
  on public.dispute_cases (case_number) where case_number is not null;
create index if not exists ix_dispute_cases_status on public.dispute_cases (status);
create index if not exists ix_dispute_cases_severity on public.dispute_cases (severity);
create index if not exists ix_dispute_cases_assigned on public.dispute_cases (assigned_to);
create index if not exists ix_dispute_cases_actor on public.dispute_cases (actor_employee_id);

drop trigger if exists trg_dispute_cases_updated_at on public.dispute_cases;
create trigger trg_dispute_cases_updated_at
  before update on public.dispute_cases
  for each row execute function public.tg_set_updated_at();

alter table public.dispute_cases enable row level security;

-- نطاق assigned_cases: المحقّق المكلّف يرى قضاياه؛ الأطراف يرون قضاياهم؛ المخوّل يرى الكل
drop policy if exists dispute_cases_select on public.dispute_cases;
create policy dispute_cases_select on public.dispute_cases
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or assigned_to = public.current_employee_id()
    or actor_employee_id = public.current_employee_id()
    or respondent_employee_id = public.current_employee_id()
  );

-- إنشاء قضية: المخوّل، أو الموظف يفتح شكوى بنفسه بصفته actor
drop policy if exists dispute_cases_insert on public.dispute_cases;
create policy dispute_cases_insert on public.dispute_cases
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or actor_employee_id = public.current_employee_id()
  );

-- تحديث: المخوّل بالإدارة أو المحقّق المكلّف على قضاياه (assigned_cases scope)
drop policy if exists dispute_cases_update on public.dispute_cases;
create policy dispute_cases_update on public.dispute_cases
  for update to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or assigned_to = public.current_employee_id()
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or assigned_to = public.current_employee_id()
  );

drop policy if exists dispute_cases_delete on public.dispute_cases;
create policy dispute_cases_delete on public.dispute_cases
  for delete to authenticated
  using (public.current_is_full_access() or public.has_permission('disputes.case.manage'));

-- =====================================================================
-- Table: dispute_sessions  (جلسات النزاع / التحقيق)
-- =====================================================================
create table if not exists public.dispute_sessions (
  id                 uuid primary key default gen_random_uuid(),
  case_id            uuid not null references public.dispute_cases(id) on delete cascade,
  session_type       text not null default 'hearing'
                       check (session_type in ('hearing','investigation','mediation','follow_up','decision')),
  scheduled_at       timestamptz,
  held_at            timestamptz,
  location           text,
  status             text not null default 'scheduled'
                       check (status in ('scheduled','held','postponed','cancelled')),
  chaired_by         uuid references public.employees(id) on delete set null,
  minutes            text,
  outcome            text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.dispute_sessions is
  'جلسات التحقيق والاستماع والوساطة المرتبطة بقضية نزاع، مع محضر ونتيجة.';

create index if not exists ix_dispute_sessions_case on public.dispute_sessions (case_id);
create index if not exists ix_dispute_sessions_status on public.dispute_sessions (status);

drop trigger if exists trg_dispute_sessions_updated_at on public.dispute_sessions;
create trigger trg_dispute_sessions_updated_at
  before update on public.dispute_sessions
  for each row execute function public.tg_set_updated_at();

alter table public.dispute_sessions enable row level security;

-- يتبع نطاق القضية الأم (assigned_cases): من يرى القضية يرى جلساتها
drop policy if exists dispute_sessions_select on public.dispute_sessions;
create policy dispute_sessions_select on public.dispute_sessions
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_sessions.case_id
        and (
          c.assigned_to = public.current_employee_id()
          or c.actor_employee_id = public.current_employee_id()
          or c.respondent_employee_id = public.current_employee_id()
        )
    )
  );

drop policy if exists dispute_sessions_write on public.dispute_sessions;
create policy dispute_sessions_write on public.dispute_sessions
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_sessions.case_id and c.assigned_to = public.current_employee_id()
    )
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_sessions.case_id and c.assigned_to = public.current_employee_id()
    )
  );

-- =====================================================================
-- Table: dispute_evidence  (أدلة النزاع)
-- =====================================================================
create table if not exists public.dispute_evidence (
  id                 uuid primary key default gen_random_uuid(),
  case_id            uuid not null references public.dispute_cases(id) on delete cascade,
  session_id         uuid references public.dispute_sessions(id) on delete set null,
  evidence_type      text not null default 'document'
                       check (evidence_type in ('document','photo','video','audio','statement','testimony','other')),
  title              text not null,
  description        text,
  file_url           text,
  submitted_by       uuid references public.employees(id) on delete set null,
  is_confidential    boolean not null default true,
  submitted_at       timestamptz not null default now(),
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.dispute_evidence is
  'الأدلة والمستندات المرفقة بقضايا النزاع وجلساتها.';

create index if not exists ix_dispute_evidence_case on public.dispute_evidence (case_id);
create index if not exists ix_dispute_evidence_session on public.dispute_evidence (session_id);

drop trigger if exists trg_dispute_evidence_updated_at on public.dispute_evidence;
create trigger trg_dispute_evidence_updated_at
  before update on public.dispute_evidence
  for each row execute function public.tg_set_updated_at();

alter table public.dispute_evidence enable row level security;

-- يتبع نطاق القضية الأم (assigned_cases)
drop policy if exists dispute_evidence_select on public.dispute_evidence;
create policy dispute_evidence_select on public.dispute_evidence
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_evidence.case_id
        and (
          c.assigned_to = public.current_employee_id()
          or c.actor_employee_id = public.current_employee_id()
          or c.respondent_employee_id = public.current_employee_id()
        )
    )
  );

drop policy if exists dispute_evidence_write on public.dispute_evidence;
create policy dispute_evidence_write on public.dispute_evidence
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_evidence.case_id and c.assigned_to = public.current_employee_id()
    )
  )
  with check (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or exists (
      select 1 from public.dispute_cases c
      where c.id = dispute_evidence.case_id and c.assigned_to = public.current_employee_id()
    )
  );

-- =====================================================================
-- Table: committee_members  (أعضاء لجان النزاع/التحقيق)
-- =====================================================================
create table if not exists public.committee_members (
  id                 uuid primary key default gen_random_uuid(),
  case_id            uuid references public.dispute_cases(id) on delete cascade,
  committee_name     text,
  employee_id        uuid not null references public.employees(id) on delete cascade,
  role_in_committee  text not null default 'member'
                       check (role_in_committee in ('chair','member','secretary','observer','advisor')),
  is_active          boolean not null default true,
  appointed_at       timestamptz not null default now(),
  removed_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz,
  created_by         uuid references auth.users(id)
);
comment on table public.committee_members is
  'أعضاء لجان التحقيق/النزاع مع دور العضو (رئيس/عضو/مقرّر) وحالة العضوية.';

create index if not exists ix_committee_members_case on public.committee_members (case_id);
create index if not exists ix_committee_members_employee on public.committee_members (employee_id);
create unique index if not exists ux_committee_members_case_emp
  on public.committee_members (case_id, employee_id)
  where case_id is not null;

drop trigger if exists trg_committee_members_updated_at on public.committee_members;
create trigger trg_committee_members_updated_at
  before update on public.committee_members
  for each row execute function public.tg_set_updated_at();

alter table public.committee_members enable row level security;

-- العضو يرى عضويته؛ من يرى القضية يرى أعضاءها؛ الكتابة للمخوّل بالإدارة
drop policy if exists committee_members_select on public.committee_members;
create policy committee_members_select on public.committee_members
  for select to authenticated
  using (
    public.current_is_full_access()
    or public.has_permission('disputes.case.manage')
    or employee_id = public.current_employee_id()
    or (
      case_id is not null and exists (
        select 1 from public.dispute_cases c
        where c.id = committee_members.case_id
          and (
            c.assigned_to = public.current_employee_id()
            or c.actor_employee_id = public.current_employee_id()
            or c.respondent_employee_id = public.current_employee_id()
          )
      )
    )
  );

drop policy if exists committee_members_write on public.committee_members;
create policy committee_members_write on public.committee_members
  for all to authenticated
  using (public.current_is_full_access() or public.has_permission('disputes.case.manage'))
  with check (public.current_is_full_access() or public.has_permission('disputes.case.manage'));

-- =====================================================================
-- RPC: mark_notification_read  (وضع علامة مقروء على إشعار المالك)
-- =====================================================================
create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns public.notifications
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.notifications;
begin
  update public.notifications
     set is_read = true,
         read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_user_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'notification not found or not owned by current user' using errcode = '42501';
  end if;

  return v_row;
end;
$$;
comment on function public.mark_notification_read(uuid) is
  'وضع علامة مقروء على إشعار يملكه المستخدم الحالي فقط (owner-scoped).';
revoke execute on function public.mark_notification_read(uuid) from public;
grant  execute on function public.mark_notification_read(uuid) to authenticated;

-- =====================================================================
-- RPC: mark_all_notifications_read  (تعليم كل إشعارات المالك كمقروءة)
-- =====================================================================
create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  update public.notifications
     set is_read = true,
         read_at = coalesce(read_at, now())
   where recipient_user_id = auth.uid()
     and is_read = false;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
comment on function public.mark_all_notifications_read() is
  'تعليم جميع إشعارات المستخدم الحالي غير المقروءة كمقروءة، وإرجاع عددها.';
revoke execute on function public.mark_all_notifications_read() from public;
grant  execute on function public.mark_all_notifications_read() to authenticated;

-- =====================================================================
-- RPC: acknowledge_decision  (تسجيل قراءة/إقرار قرار للموظف الحالي)
-- =====================================================================
create or replace function public.acknowledge_decision(
  p_decision_id uuid,
  p_acknowledge boolean default true
)
returns public.decision_reads
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_row  public.decision_reads;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- يجب أن يكون الموظف مستهدفاً بالقرار (target-scoped)
  if not exists (
    select 1 from public.decision_recipients dr
    where dr.decision_id = p_decision_id and dr.employee_id = v_me
  ) then
    raise exception 'decision not targeted to current employee' using errcode = '42501';
  end if;

  insert into public.decision_reads (
    decision_id, employee_id, read_at, acknowledged, acknowledged_at, created_by
  ) values (
    p_decision_id, v_me, now(), coalesce(p_acknowledge, false),
    case when p_acknowledge then now() else null end, auth.uid()
  )
  on conflict (decision_id, employee_id) do update
    set acknowledged    = greatest(public.decision_reads.acknowledged::int, excluded.acknowledged::int)::boolean,
        acknowledged_at = coalesce(public.decision_reads.acknowledged_at, excluded.acknowledged_at),
        updated_at      = now()
  returning * into v_row;

  return v_row;
end;
$$;
comment on function public.acknowledge_decision(uuid, boolean) is
  'تسجيل إيصال قراءة/إقرار قرار إداري للموظف الحالي، شرط أن يكون ضمن المستهدفين (target-scoped).';
revoke execute on function public.acknowledge_decision(uuid, boolean) from public;
grant  execute on function public.acknowledge_decision(uuid, boolean) to authenticated;

-- =====================================================================
-- نهاية Migration 0008
-- =====================================================================
