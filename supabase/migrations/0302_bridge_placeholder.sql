-- Migration 0302: bridge no-op
-- سد فجوة تسلسل بعد إعادة ترقيم.
do $$ begin null; end $$;
