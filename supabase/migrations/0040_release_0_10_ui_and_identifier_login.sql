-- Migration 0040: publish the 0.10.0 staging candidate metadata.
-- The release remains optional until runtime, device and signing gates pass.
begin;

update public.app_release_policies
set latest_version = '0.10.0',
    latest_build = 10,
    min_supported_version = case
      when environment in ('development','staging') then '0.10.0'
      else '0.9.0'
    end,
    min_supported_build = case
      when environment in ('development','staging') then 10
      else 9
    end,
    force_update = false,
    update_message_ar = 'يتوفر إصدار 0.10.0 بتجربة استخدام محسنة وتسجيل دخول بالبريد أو الهاتف أو كود الموظف.',
    updated_at = now()
where platform in ('android','ios','web')
  and environment in ('development','staging','production');

commit;
