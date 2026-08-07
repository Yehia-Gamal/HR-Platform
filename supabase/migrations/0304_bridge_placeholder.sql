-- Migration 0304: bridge no-op
-- سد فجوة تسلسل بعد إعادة ترقيم.
do $$ begin null; end $$;
