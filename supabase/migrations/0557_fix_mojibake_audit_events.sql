-- =====================================================================
-- 0557: إصلاح النص العربي التالف في سجل التدقيق (audit_events)
--
-- تكملة 0556: نفس التلف (عربي فُسِّر كـ cp1252 → «Ø¬.Ù…») وصل إلى
-- audit_events.summary_ar (81) و audit_events.description (28) من الدوال
-- الـ12 قبل إصلاحها. أُجِّل في 0556 لأنه سجل رسمي، ثم اعتمده صاحب النظام.
--
-- إعادة ترميز فقط: لا يتغير معنى أي سجل ولا تاريخه ولا فاعله — تُعاد
-- «سلاسل التلف» إلى حروفها العربية الأصلية، وأي نص سليم في نفس السجل لا يُمس.
-- المساعد هو نفسه المختبَر في 0556 (تطابق تام على نص اصطناعي).
-- =====================================================================

begin;

create or replace function pg_temp.fix_mojibake(p text)
returns text
language plpgsql
as $fx$
declare
  v_out text := '';
  v_run text := '';
  v_ch text;
  v_code int;
  i int;
  -- ما يولّده التلف: 0x80–0xFF + رموز cp1252 الموسّعة
  v_cp constant text := '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';

begin
  if p is null then return null; end if;
  for i in 1 .. char_length(p) + 1 loop
    v_ch := case when i <= char_length(p) then substr(p, i, 1) else null end;
    v_code := coalesce(ascii(v_ch), 0);
    if v_ch is not null and ((v_code between 128 and 255) or strpos(v_cp, v_ch) > 0) then
      v_run := v_run || v_ch;
    else
      if v_run <> '' then
        v_out := v_out || pg_temp.decode_run(v_run);
        v_run := '';
      end if;
      if v_ch is not null then v_out := v_out || v_ch; end if;
    end if;
  end loop;
  return v_out;
end;
$fx$;

create or replace function pg_temp.decode_run(p text)
returns text
language plpgsql
as $dr$
declare
  v_bytes bytea := ''::bytea;
  v_ch text;
  v_code int;
  i int;
begin
  for i in 1 .. char_length(p) loop
    v_ch := substr(p, i, 1);
    v_code := ascii(v_ch);
    if v_code < 256 then
      v_bytes := v_bytes || set_byte('\x00'::bytea, 0, v_code);
    else
      v_bytes := v_bytes || convert_to(v_ch, 'WIN1252');
    end if;
  end loop;
  return convert_from(v_bytes, 'UTF8');
exception when others then
  return p;  -- ليست سلسلة تلف (مثل «—» أصلية) — تُترك كما هي
end;
$dr$;


update public.audit_events
   set summary_ar  = pg_temp.fix_mojibake(summary_ar),
       description = pg_temp.fix_mojibake(description)
 where summary_ar ~ '(Ø|Ù|ðŸ|â€)' or description ~ '(Ø|Ù|ðŸ|â€)';

commit;
