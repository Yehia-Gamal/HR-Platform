const https = require('https');

const HOST = 'ujzzvqsodyhnnnpkoaml.supabase.co';
const KEY = 'sb_publishable_Q5JTOX-mLp5Y9wmxlZyTnQ_QBu5wPC2';

function rpc(fn) {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: HOST,
      path: '/rest/v1/rpc/' + fn,
      method: 'POST',
      headers: {
        'apikey': KEY,
        'Authorization': 'Bearer ' + KEY,
        'Content-Type': 'application/json',
      },
    }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ fn, status: res.statusCode, body: d.slice(0, 150) }));
    });
    req.on('error', e => resolve({ fn, status: 'ERR', body: e.message }));
    req.write(JSON.stringify({}));
    req.end();
  });
}

(async () => {
  const fns = ['admin_reinstate_device', 'admin_revoke_device', 'approve_device', 'decide_request', 'register_my_device'];
  for (const fn of fns) {
    const r = await rpc(fn);
    const label = r.status === 400 || r.status === 401 ? 'EXISTS ✓' : r.status === 404 ? 'MISSING ✗' : `HTTP ${r.status} ?`;
    console.log(fn.padEnd(30), label, r.status === 404 ? '' : `| ${r.body}`);
  }
})();
