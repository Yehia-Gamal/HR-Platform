-- Migration 0300: جسر ترقيم (no-op) — لسد فجوة تسلسل الترحيلات.
do $$
begin
  null;
end $$;
