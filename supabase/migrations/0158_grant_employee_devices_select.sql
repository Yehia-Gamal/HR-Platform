-- 0158: GRANT SELECT on employee_devices to authenticated.
-- RLS (migration 0073) already filters rows (owner + full_access + manage_devices).
-- But the table-level GRANT was missing, blocking all authenticated reads.
-- Required by device approval workflow (0145) — admin/employee needs to read device status.

grant select on public.employee_devices to authenticated;
