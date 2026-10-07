-- 0619: Temporarily close Honor Board for updates as requested by user
-- إغلاق لوحة الشرف مؤقتاً للتحديث والتطوير

create or replace function public.get_honor_board(p_month text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- مغلقة مؤقتاً للتطوير والتحديث
  return '[]'::jsonb;
end;
$$;

grant execute on function public.get_honor_board(text) to authenticated, anon;
