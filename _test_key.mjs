// Temporary test — delete after use
const BASE = 'https://ujzzvqsodyhnnnpkoaml.supabase.co';
const PUB_KEY = 'sb_publishable_Q5JTOX-mLp5Y9wmxlZyTnQ_QBu5wPC2';

async function test() {
  // 1. Test REST API
  const rest = await fetch(`${BASE}/rest/v1/`, { headers: { apikey: PUB_KEY } });
  console.log('REST:', rest.status, rest.status === 200 ? 'OK' : await rest.text());

  // 2. Test Auth endpoint
  const auth = await fetch(`${BASE}/auth/v1/settings`, { headers: { apikey: PUB_KEY } });
  console.log('AUTH:', auth.status, auth.status === 200 ? 'OK' : await auth.text());

  // 3. Test Edge Functions
  const fn = await fetch(`${BASE}/functions/v1/identifier-sign-in`, {
    method: 'POST',
    headers: { apikey: PUB_KEY, Authorization: `Bearer ${PUB_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ identifier: 'test' }),
  });
  console.log('EDGE:', fn.status, await fn.text());
}
test().catch(e => console.error('NETWORK ERROR:', e.message));
