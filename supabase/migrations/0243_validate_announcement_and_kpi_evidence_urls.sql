-- 0243_validate_announcement_and_kpi_evidence_urls.sql
-- ═══════════════════════════════════════════════════════════════════════
-- متابعة لـ 0235: توسيع التحقق الخادمي ليشمل أعمدة روابط إضافية يتحكم بها
-- العميل وكانت تُخزَّن دون أي تحقق (نفس خطر Stored-XSS / SSRF عند العرض):
--
--   • announcements.banner_url   — يُضبَط عبر RPC publish_official_announcement
--                                   (0177) بـ nullif(trim(...)) فقط، بلا تحقق مخطط.
--   • kpi_evidence.external_url  — يُضبَط عبر RPC add_kpi_evidence (0166) كرابط
--                                   حر تماماً بلا أي تحقق.
--   • kpi_evidence.storage_path  — مسار كائن تخزين؛ يجب أن يكون نسبياً بحتاً.
--
-- الحل: إعادة استخدام دوال التحقق الموجودة من 0235 (لا نُعيد تعريفها):
--   public.is_safe_url_or_path(text)   لروابط https المطلقة أو المسارات النسبية (banner_url)
--   public.is_safe_storage_path(text)  لمسارات التخزين النسبية البحتة (storage_path)
-- ونضيف هنا دالة واحدة جديدة:
--   public.is_safe_external_link(text) — كـ is_safe_url_or_path لكن تسمح http أيضاً،
--     لأن external_url رابط مرجعي حر يلصقه المستخدم (قد يكون http) ويُعرَض كـ href.
-- ثم محفّزات BEFORE INSERT/UPDATE على العمودين/الأعمدة المعنية، بحيث يُغطّى كل
-- مسار كتابة (RPCs + أي تحديث RLS مباشر + أي RPC مستقبلي).
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ─── 0) رابط دليل خارجي آمن: http/https مطلق أو مسار نسبي ───
-- خاص بـ kpi_evidence.external_url: المستخدم يلصق رابطاً مرجعياً حراً (Drive،
-- مستند مشترك، نظام قديم داخلي) قد يكون http://، لذا نسمح http و https معاً
-- بينما نرفض المخططات الخطِرة نفسها (data/javascript/blob/file/...). الرابط
-- يُعرَض كـ href لا كـ src، فالمخاطر محصورة في مخططات التنفيذ لا في http العادي.
create or replace function public.is_safe_external_link(p_value text)
returns boolean
language sql
immutable
parallel safe
as $$
  select case
    when p_value is null or length(trim(p_value)) = 0 then true
    -- رفض محارف التحكّم و newline/CR/tab (تُستخدم لتجاوز الفلاتر)
    when p_value ~ '[[:cntrl:]]' then false
    -- رفض المخططات الخطِرة صراحةً (غير حسّاس لحالة الأحرف، مع تجاهل مسافات بادئة)
    when lower(ltrim(p_value)) ~ '^(data|file|javascript|blob|vbscript|about|filesystem):' then false
    -- رفض أي مخطط عدا http/https
    when p_value ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' and lower(ltrim(p_value)) !~ '^https?://' then false
    -- رفض الروابط بلا-مخطط (//host) و UNC (\\host)
    when ltrim(p_value) ~ '^(//|\\\\)' then false
    -- منع اجتياز المسار في المسارات النسبية
    when p_value ~ '(^|/)\.\.(/|$)' then false
    else true
  end;
$$;

comment on function public.is_safe_external_link(text) is
  'يتحقق أن القيمة رابط http/https مطلق أو مسار نسبي آمن. يرفض data:/file:/javascript:/blob:/vbscript: ومحارف التحكّم واجتياز المسار (..). فارغ/NULL مسموح. أوسع من is_safe_url_or_path (يسمح http) لروابط الأدلة المرجعية.';

revoke all on function public.is_safe_external_link(text) from public;
grant execute on function public.is_safe_external_link(text) to authenticated, service_role;

-- ─── 1) محفّز announcements.banner_url ───
create or replace function public.tg_announcements_validate_banner_url()
returns trigger
language plpgsql
as $$
begin
  if new.banner_url is not null
     and not public.is_safe_url_or_path(new.banner_url) then
    raise exception 'invalid_banner_url'
      using errcode = '22023',
            detail  = 'banner_url must be an https URL or a relative storage path; data:/file:/javascript: schemes and path traversal are rejected.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_announcements_validate_banner_url on public.announcements;
create trigger trg_announcements_validate_banner_url
  before insert or update of banner_url on public.announcements
  for each row execute function public.tg_announcements_validate_banner_url();

-- ─── 2) محفّز kpi_evidence.external_url + storage_path ───
-- عمودان في نفس الجدول: external_url رابط مرجعي (http/https/نسبي)،
-- و storage_path مسار كائن نسبي بحت.
create or replace function public.tg_kpi_evidence_validate_urls()
returns trigger
language plpgsql
as $$
begin
  if new.external_url is not null
     and not public.is_safe_external_link(new.external_url) then
    raise exception 'invalid_external_url'
      using errcode = '22023',
            detail  = 'external_url must be an http/https URL or a relative path; data:/file:/javascript:/blob: schemes and path traversal are rejected.';
  end if;

  if new.storage_path is not null
     and not public.is_safe_storage_path(new.storage_path) then
    raise exception 'invalid_storage_path'
      using errcode = '22023',
            detail  = 'storage_path must be a relative storage object path; any URL scheme, absolute path, or path traversal is rejected.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_kpi_evidence_validate_urls on public.kpi_evidence;
create trigger trg_kpi_evidence_validate_urls
  before insert or update of external_url, storage_path on public.kpi_evidence
  for each row execute function public.tg_kpi_evidence_validate_urls();

commit;
