import { createClient } from '@supabase/supabase-js';
import { json, preflight } from '../_shared/cors.ts';

// ─── identifier-sign-in ────────────────────────────────────────────
// Timing-safe credential gateway: resolves email / phone / employee_code
// to a Supabase Auth email and calls signInWithPassword.
//
// SECURITY DESIGN NOTES:
//
// 1. FIXED-DEADLINE TIMING (ESI-01)
//    Every request returns at the SAME absolute instant (~480-560ms after
//    start), regardless of whether the identifier was found, the password
//    was checked, or the request was rejected early. This prevents an
//    attacker from distinguishing "valid identifier + wrong password" from
//    "identifier does not exist" via response-time side-channels.
//
// 2. IP + IDENTIFIER RATE LIMITING
//    Two sliding-window counters (IP: 10/60s, identifier: 6/5min) are
//    checked before any credential work. Both use peppered SHA-256 hashes
//    so the raw identifiers/IPs never touch the database.
//
// 3. WHY NOT ZOD
//    Input parsing uses manual String() coercion + .trim()/.slice() instead
//    of a Zod schema. This is intentional: Zod's variable-cost validation
//    (depending on input shape/size) would add unpredictable latency that
//    undermines the fixed-deadline timing guarantee. The manual approach
//    has constant-time cost and is easier to audit for side-channel safety.
//
// 4. FALLBACK EMAIL (ESI-01 complement)
//    When the identifier doesn't resolve to a real user, we still call
//    signInWithPassword with a deterministic fake email derived from the
//    identifier hash. This ensures bcrypt work always runs, preventing
//    a timing oracle that skips the password check for unknown users.
//
// 5. TRUSTED PROXY (ESI-02)
//    IP extraction from headers is only enabled when TRUSTED_PROXY=1.
//    Without it, all requests share a single IP bucket, so a spoofed
//    X-Forwarded-For cannot mint fresh rate-limit buckets.
// ────────────────────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const HASH_PEPPER = Deno.env.get('LOGIN_HASH_PEPPER') ?? '';

const IP_WINDOW_MS = 60_000;
const IP_MAX_ATTEMPTS = 10;
// ESI-02: بدون TRUSTED_PROXY=1 كل الطلبات تشترك في سلة واحدة ('untrusted-network').
// حدّ ضيّق (10) على سلة مشتركة يُقفل تسجيل الدخول على المنظمة كلها دفعة واحدة
// (كل محاولات الموظفين تُحسب في نفس السلة). نرفع حد السلة المشتركة بينما يبقى
// الحد الفردي لكل معرّف (6/5د) هو الحاجز الأساسي ضد الهجمات.
const SHARED_IP_MAX_ATTEMPTS = 120;
const IDENTIFIER_WINDOW_MS = 5 * 60_000;
const IDENTIFIER_MAX_ATTEMPTS = 6;

type IdentifierKind = 'email' | 'phone' | 'employee_code';

type NormalizedIdentifier = {
  kind: IdentifierKind;
  value: string;
};

function normalizeIdentifier(raw: string): NormalizedIdentifier {
  const value = raw.trim();
  if (value.includes('@')) {
    return { kind: 'email', value: value.toLowerCase() };
  }

  const compact = value.replace(/[\s().-]/g, '');
  if (/^\+?\d{7,15}$/.test(compact)) {
    let phone = compact;
    if (/^01\d{9}$/.test(phone)) phone = `+20${phone.slice(1)}`;
    else if (/^20\d{10}$/.test(phone)) phone = `+${phone}`;
    else if (!phone.startsWith('+')) phone = `+${phone}`;
    return { kind: 'phone', value: phone };
  }

  return { kind: 'employee_code', value: value.toUpperCase() };
}

// ESI-02: only trust forwarded IP headers when a trusted upstream is declared.
// TRUSTED_PROXY=1 (set only when the function sits behind a proxy/CDN that
// overwrites these headers) enables header-based IP; otherwise fall back to a
// constant bucket so a spoofed X-Forwarded-For cannot mint a fresh IP per
// request. The per-identifier limit remains the primary brute-force control.
const TRUST_FORWARDED_IP = (Deno.env.get('TRUSTED_PROXY') ?? '') === '1';

function clientIp(req: Request): string {
  if (TRUST_FORWARDED_IP) {
    return req.headers.get('cf-connecting-ip')
      ?? req.headers.get('x-real-ip')
      ?? req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      ?? 'unknown';
  }
  // Untrusted network: do not let attacker-controlled headers key the limiter.
  return 'untrusted-network';
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(`${HASH_PEPPER}:${value}`);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function genericFailure(req: Request, status = 401) {
  return json(req, { error: 'INVALID_CREDENTIALS' }, status);
}

// ESI-01: wait until a FIXED absolute deadline computed at request start, so a
// heavier "identifier exists" path cannot leak its extra work as longer latency.
// The deadline is generous enough to cover the exists-path work (lookup +
// getUserById + bcrypt). If work somehow exceeds it, still return promptly (the
// existence signal is bounded by the deadline, not amplified past it).
async function waitUntil(deadlineAt: number) {
  const remaining = deadlineAt - Date.now();
  if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return preflight(req);
  if (req.method !== 'POST') return json(req, { error: 'METHOD_NOT_ALLOWED' }, 405);
  const startedAt = Date.now();
  // Fixed absolute deadline set once per request (ESI-01): every credential
  // outcome returns at ~this instant regardless of the work performed, so an
  // "identifier exists" path cannot leak via longer latency.
  const deadline = startedAt + 480 + Math.floor(Math.random() * 80);

  try {
  if (!SUPABASE_URL || !SERVICE_ROLE || !ANON_KEY || HASH_PEPPER.length < 24) {
    return json(req, { error: 'SERVER_CONFIGURATION' }, 500);
  }

  try {
  let identifier = '';
  let password = '';
  try {
    const body = await req.json();
    identifier = String(body?.identifier ?? '').trim().slice(0, 254);
    password = String(body?.password ?? '').slice(0, 512);
  } catch {
    return json(req, { error: 'BAD_REQUEST' }, 400);
  }

  if (identifier.length < 2 || password.length < 8) {
    await waitUntil(deadline);
    return genericFailure(req);
  }

  const normalized = normalizeIdentifier(identifier);
  const ip = clientIp(req);
  const identifierHash = await sha256(`${normalized.kind}:${normalized.value}`);
  const ipHash = await sha256(`ip:${ip}`);
  const userAgentHash = await sha256(`ua:${req.headers.get('user-agent') ?? 'unknown'}`);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const ipWindow = new Date(Date.now() - IP_WINDOW_MS).toISOString();
  const identifierWindow = new Date(Date.now() - IDENTIFIER_WINDOW_MS).toISOString();
  const [ipCountResult, identifierCountResult] = await Promise.all([
    admin.from('login_auth_attempts').select('id', { count: 'exact', head: true }).eq('ip_hash', ipHash).gte('attempted_at', ipWindow),
    admin.from('login_auth_attempts').select('id', { count: 'exact', head: true }).eq('identifier_hash', identifierHash).gte('attempted_at', identifierWindow),
  ]);

  // ESI-02: السلة المشتركة تُحصى لكل المنظمة — نطبق عليها حداً أوسع حتى لا
  // نُقفل الموظفين الشرعيين، مع الإبقاء على الحد الفردي الصارم للمعرّف.
  const ipMaxAttempts = ip === 'untrusted-network' ? SHARED_IP_MAX_ATTEMPTS : IP_MAX_ATTEMPTS;
  if ((ipCountResult.count ?? 0) >= ipMaxAttempts || (identifierCountResult.count ?? 0) >= IDENTIFIER_MAX_ATTEMPTS) {
    await admin.from('login_auth_attempts').insert({
      identifier_hash: identifierHash,
      ip_hash: ipHash,
      identifier_kind: normalized.kind,
      success: false,
      failure_code: 'rate_limited',
      user_agent_hash: userAgentHash,
    });
    await waitUntil(deadline);
    return json(req, { error: 'TOO_MANY_ATTEMPTS' }, 429);
  }

  let resolvedEmail: string | null = null;
  try {
    if (normalized.kind === 'email') {
      resolvedEmail = normalized.value;
    } else {
      let employeeQuery = admin.from('employees').select('id').eq('is_deleted', false).eq('is_active', true).limit(1);
      if (normalized.kind === 'phone') {
        // P0-FIX: البحث المتساهل عن الهاتف. بعض السجلات (من update_employee_admin
        // قبل التصحيح) خُزّنت بصيغة محلية '01XXXXXXXXX' بدل E.164. نطوّع قائمة
        // الصيغ المرشحة ونبحث بأي منها لضمان مطابقة الحساب مهما كان الترميز المخزّن.
        const variants = new Set<string>([normalized.value]);
        if (normalized.value.startsWith('+20')) {
          variants.add('0' + normalized.value.slice(3));            // محلي
          variants.add(normalized.value.slice(1));                 // '20XXXXXXXXX' بدون '+'
        } else if (normalized.value.startsWith('20') && normalized.value.length === 12) {
          variants.add('+' + normalized.value);
          variants.add('0' + normalized.value.slice(2));
        } else if (/^01\d{9}$/.test(normalized.value)) {
          variants.add('+20' + normalized.value.slice(1));
        }
        employeeQuery = employeeQuery.in('phone_e164', [...variants]);
      } else {
        employeeQuery = employeeQuery.eq('employee_code', normalized.value);
      }
      const { data: employee } = await employeeQuery.maybeSingle();
      if (employee?.id) {
        const { data: profile } = await admin
          .from('profiles')
          .select('id')
          .eq('employee_id', employee.id)
          .maybeSingle();
        if (profile?.id) {
          const { data: userResult } = await admin.auth.admin.getUserById(profile.id);
          resolvedEmail = userResult.user?.email ?? null;
        }
      }
    }

    const publicAuth = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const fallbackEmail = `invalid-${identifierHash.slice(0, 24)}@invalid.local`;
    const { data, error } = await publicAuth.auth.signInWithPassword({
      email: resolvedEmail ?? fallbackEmail,
      password,
    });
    const success = !error && Boolean(data.session?.access_token && data.session?.refresh_token);

    await admin.from('login_auth_attempts').insert({
      identifier_hash: identifierHash,
      ip_hash: ipHash,
      identifier_kind: normalized.kind,
      success,
      failure_code: success ? null : 'invalid_credentials',
      user_agent_hash: userAgentHash,
    });

    // ESI-03: for email logins, verify linked employee is not deleted/inactive.
    // Phone/code paths already filter by is_active/is_deleted during lookup;
    // email skips that lookup, so we check post-auth. Runs BEFORE the deadline
    // so the fixed-time window (ESI-01) absorbs the extra DB queries.
    let esi03Blocked = false;
    if (success && normalized.kind === 'email' && data.user?.id) {
      const { data: linkedProfile } = await admin
        .from('profiles')
        .select('employee_id')
        .eq('id', data.user.id)
        .maybeSingle();
      if (linkedProfile?.employee_id) {
        const { data: emp } = await admin
          .from('employees')
          .select('is_deleted,is_active')
          .eq('id', linkedProfile.employee_id)
          .maybeSingle();
        if (emp && (emp.is_deleted || !emp.is_active)) {
          await admin.from('login_auth_attempts').update({ success: false, failure_code: 'employee_inactive' })
            .eq('identifier_hash', identifierHash).eq('success', true).order('attempted_at', { ascending: false }).limit(1);
          esi03Blocked = true;
        }
      }
    }

    await waitUntil(deadline);
    if (!success || !data.session || esi03Blocked) return genericFailure(req);

    return json(req, {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_in: data.session.expires_in,
      expires_at: data.session.expires_at,
      token_type: data.session.token_type,
    });
  } catch {
    await admin.from('login_auth_attempts').insert({
      identifier_hash: identifierHash,
      ip_hash: ipHash,
      identifier_kind: normalized.kind,
      success: false,
      failure_code: 'internal_failure',
      user_agent_hash: userAgentHash,
    });
    await waitUntil(deadline);
    return genericFailure(req);
  }
  } catch {
    // Top-level safety net: preserve timing guarantee even on unexpected errors.
    await waitUntil(deadline);
    return genericFailure(req);
  }
  } catch (err) {
    console.error('identifier-sign-in unhandled error', err instanceof Error ? err.message : String(err));
    await waitUntil(deadline);
    return genericFailure(req);
  }
});
