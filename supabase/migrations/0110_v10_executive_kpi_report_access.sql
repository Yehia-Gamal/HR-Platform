-- V10: the executive director receives aggregated KPI reports but never approves scores.
begin;

insert into public.role_permissions(role_id,permission_id,scope,requires_mfa,requires_reason)
select r.id,p.id,'organization',false,false
from public.roles r
join public.permissions p on p.code='performance.kpi.report.read'
where r.slug in ('executive','executive-director')
on conflict(role_id,permission_id,scope) do update set effective_to=null;

commit;
