import { createClient } from '@supabase/supabase-js';
import { corsHeaders } from '../_shared/cors.ts';
import { timingSafeEqual } from '../_shared/secret.ts';

// scheduled-report-runner: cron-triggered Edge Function that:
// 1. Queues due scheduled reports via queue_due_scheduled_reports() RPC
// 2. Processes queued report_runs by generating structured JSON data
// 3. Stores results in report_runs.result_summary
// 4. Notifies the audience via notification_jobs
//
// Supported report_type values (from admin UI):
//   executive_daily  — headcount, attendance, disputes, KPI, pending actions
//   manager_weekly   — team attendance, pending requests, team KPI
//   hr_monthly       — headcount trends, hires/terms, attendance overview

type SupabaseClient = ReturnType<typeof createClient>;

interface ReportRun {
  id: string;
  report_type: string;
  audience_snapshot: { scope?: string; config?: Record<string, unknown> } | null;
  scheduled_report_id: string | null;
}

/** Report data generator registry — maps report_type to a function that
 *  queries real tables and returns structured JSON for result_summary. */
type ReportGenerator = (sb: SupabaseClient, run: ReportRun) => Promise<Record<string, unknown>>;

const generators: Record<string, ReportGenerator> = {
  executive_daily: generateExecutiveDaily,
  manager_weekly: generateManagerWeekly,
  hr_monthly: generateHrMonthly,
};

// ─── Report generators ──────────────────────────────────────────────

async function generateExecutiveDaily(sb: SupabaseClient, _run: ReportRun) {
  const today = new Date().toISOString().slice(0, 10);

  const [headcount, attendanceToday, disputes, pendingRequests, kpiCycles] = await Promise.all([
    sb.from('employees').select('id', { count: 'exact', head: true }).eq('status', 'active'),
    sb.from('attendance_daily').select('status', { count: 'exact' }).eq('work_date', today),
    sb.from('dispute_cases').select('id', { count: 'exact', head: true }).in('status', ['open', 'under_investigation', 'in_hearing', 'escalated']),
    sb.from('requests').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    sb.from('kpi_cycles').select('id,period_month,status').in('status', ['open', 'in_review']).limit(5),
  ]);

  // Attendance breakdown from today's records
  const attendanceRows = attendanceToday.data ?? [];
  const attendanceSummary = {
    total: attendanceToday.count ?? 0,
    present: attendanceRows.filter((r: { status: string }) => r.status === 'present').length,
    absent: attendanceRows.filter((r: { status: string }) => r.status === 'absent').length,
    late: attendanceRows.filter((r: { status: string }) => r.status === 'late').length,
    onLeave: attendanceRows.filter((r: { status: string }) => r.status === 'on_leave').length,
  };

  return {
    reportType: 'executive_daily',
    date: today,
    headcount: headcount.count ?? 0,
    attendance: attendanceSummary,
    openDisputes: disputes.count ?? 0,
    pendingRequests: pendingRequests.count ?? 0,
    activeKpiCycles: (kpiCycles.data ?? []).map((c: { id: string; period_month: string; status: string }) => ({
      id: c.id, month: c.period_month, status: c.status,
    })),
  };
}

async function generateManagerWeekly(sb: SupabaseClient, _run: ReportRun) {
  const now = new Date();
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - now.getDay()); // Sunday
  const weekStartStr = weekStart.toISOString().slice(0, 10);
  const todayStr = now.toISOString().slice(0, 10);

  const [headcount, attendanceWeek, pendingRequests, pendingCorrections, overtimeRequests] = await Promise.all([
    sb.from('employees').select('id', { count: 'exact', head: true }).eq('status', 'active'),
    sb.from('attendance_daily').select('status').gte('work_date', weekStartStr).lte('work_date', todayStr),
    sb.from('requests').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    sb.from('attendance_corrections').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    sb.from('overtime_records').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
  ]);

  const weekRows = attendanceWeek.data ?? [];
  const attendanceSummary = {
    totalRecords: weekRows.length,
    present: weekRows.filter((r: { status: string }) => r.status === 'present').length,
    absent: weekRows.filter((r: { status: string }) => r.status === 'absent').length,
    late: weekRows.filter((r: { status: string }) => r.status === 'late').length,
    onLeave: weekRows.filter((r: { status: string }) => r.status === 'on_leave').length,
  };

  return {
    reportType: 'manager_weekly',
    weekStart: weekStartStr,
    weekEnd: todayStr,
    headcount: headcount.count ?? 0,
    attendance: attendanceSummary,
    pendingRequests: pendingRequests.count ?? 0,
    pendingCorrections: pendingCorrections.count ?? 0,
    pendingOvertime: overtimeRequests.count ?? 0,
  };
}

async function generateHrMonthly(sb: SupabaseClient, _run: ReportRun) {
  const now = new Date();
  const monthStart = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
  const todayStr = now.toISOString().slice(0, 10);

  const [activeEmployees, newHires, terminated, attendanceMonth, openDisputes, resolvedDisputes, leaveRequests] = await Promise.all([
    sb.from('employees').select('id', { count: 'exact', head: true }).eq('status', 'active'),
    sb.from('employees').select('id', { count: 'exact', head: true }).eq('status', 'active').gte('hire_date', monthStart),
    sb.from('employees').select('id', { count: 'exact', head: true }).eq('status', 'terminated').gte('updated_at', `${monthStart}T00:00:00`),
    sb.from('attendance_daily').select('status').gte('work_date', monthStart).lte('work_date', todayStr),
    sb.from('dispute_cases').select('id', { count: 'exact', head: true }).in('status', ['open', 'under_investigation', 'in_hearing', 'escalated']),
    sb.from('dispute_cases').select('id', { count: 'exact', head: true }).in('status', ['resolved', 'closed']).gte('resolved_at', `${monthStart}T00:00:00`),
    sb.from('leave_requests').select('id', { count: 'exact', head: true }).gte('created_at', `${monthStart}T00:00:00`),
  ]);

  const monthRows = attendanceMonth.data ?? [];
  const attendanceSummary = {
    totalRecords: monthRows.length,
    present: monthRows.filter((r: { status: string }) => r.status === 'present').length,
    absent: monthRows.filter((r: { status: string }) => r.status === 'absent').length,
    late: monthRows.filter((r: { status: string }) => r.status === 'late').length,
    onLeave: monthRows.filter((r: { status: string }) => r.status === 'on_leave').length,
    attendanceRate: monthRows.length > 0
      ? Math.round((monthRows.filter((r: { status: string }) => r.status === 'present').length / monthRows.length) * 100)
      : 0,
  };

  return {
    reportType: 'hr_monthly',
    month: monthStart,
    headcount: activeEmployees.count ?? 0,
    newHires: newHires.count ?? 0,
    terminated: terminated.count ?? 0,
    attendance: attendanceSummary,
    openDisputes: openDisputes.count ?? 0,
    resolvedDisputesThisMonth: resolvedDisputes.count ?? 0,
    leaveRequestsThisMonth: leaveRequests.count ?? 0,
  };
}

// ─── Main handler ────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const cronSecret = Deno.env.get('CRON_SECRET');
  const cron = req.headers.get('x-cron-secret');
  if (!await timingSafeEqual(cron, cronSecret)) return json(req, { error: 'UNAUTHORIZED' }, 401);
  const url = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json(req, { error: 'SERVER_CONFIGURATION' }, 500);
  const supabase = createClient(url, key, { auth: { persistSession: false } });

  // 1. Queue due reports
  const { data: queued, error } = await supabase.rpc('queue_due_scheduled_reports', { p_now: new Date().toISOString() });
  if (error) { console.error('queue_due_scheduled_reports failed', error.message); return json(req, { error: 'QUEUE_FAILED' }, 500); }

  // 2. Process queued runs
  const { data: runs } = await supabase
    .from('report_runs')
    .select('id,report_type,audience_snapshot,scheduled_report_id')
    .eq('status', 'queued')
    .limit(20) as { data: ReportRun[] | null };

  let completed = 0; let failed = 0;
  for (const run of runs ?? []) {
    try {
      // Lock: move to running
      const { data: locked } = await supabase
        .from('report_runs')
        .update({ status: 'running', started_at: new Date().toISOString(), attempts: 1 })
        .eq('id', run.id).eq('status', 'queued')
        .select('id')
        .maybeSingle();
      if (!locked) continue;

      // Generate report data
      const generate = generators[run.report_type];
      const reportData = generate
        ? await generate(supabase, run)
        : { reportType: run.report_type, note: 'Unknown report type — no generator registered.', audience: run.audience_snapshot };

      const summary = {
        generatedAt: new Date().toISOString(),
        ...reportData,
      };

      // Complete the run
      const { error: completeError } = await supabase
        .from('report_runs')
        .update({ status: 'completed', completed_at: new Date().toISOString(), result_summary: summary })
        .eq('id', run.id);

      if (completeError) { failed += 1; continue; }

      // 3. Notify audience: create an in-app notification for the report owner
      if (run.scheduled_report_id) {
        const { data: schedule } = await supabase
          .from('scheduled_reports')
          .select('name_ar,created_by')
          .eq('id', run.scheduled_report_id)
          .maybeSingle();
        if (schedule?.created_by) {
          const { data: notifRows } = await supabase.from('notifications').insert({
            recipient_user_id: schedule.created_by,
            title: `تقرير جاهز: ${schedule.name_ar ?? run.report_type}`,
            body: `تم إعداد التقرير بنجاح في ${summary.generatedAt.slice(0, 16).replace('T', ' ')}`,
            category: 'system',
            priority: 'normal',
            entity_type: 'report_run',
            entity_id: run.id,
          }).select('id').maybeSingle();
          if (notifRows?.id) {
            await supabase.from('notification_jobs').insert({
              notification_id: notifRows.id,
              recipient_user_id: schedule.created_by,
              channel: 'in_app',
              status: 'sent',
              sent_at: new Date().toISOString(),
              idempotency_key: `report-run:${run.id}:in_app`,
            });
          }
        }
      }
      completed += 1;
    } catch (err) {
      console.error(`Report run ${run.id} failed:`, err);
      await supabase.from('report_runs')
        .update({ status: 'failed', completed_at: new Date().toISOString(), error_detail: String(err).replace(/https?:\/\/[^\s]+/g, '[URL]').slice(0, 500) })
        .eq('id', run.id).catch(() => {});
      failed += 1;
    }
  }
  return json(req, { queued: queued ?? 0, completed, failed });
});

function json(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(req), 'content-type': 'application/json' } });
}
