# Merge Queue — أحلى شباب HR V23

> ترتيب الدمج الإلزامي: contracts → migrations → RLS/RPC/Edge → repositories → state → UI → tests → docs
> لا يُدمج UI يعتمد Backend غير مدمج. لا `take all changes`.

## القواعد

1. **الترتيب:** يُتبع ترتيب الدمج أعلاه بصرامة.
2. **التحقق قبل الدمج:** كل PR يجب أن يجتاز CI (web-ci + flutter-ci + supabase-ci + security-ci).
3. **المراجعة:** Integration Lead (وكيل 14) يراجع كل دمج يمس ملفات مشتركة.
4. **التعارضات:** عند تعارض بين وكيلين، يُحل عبر CROSS_AGENT_REQUESTS.md.
5. **UI Integration:** في كل موجة، ليس في النهاية فقط.
6. **لا انتظار:** لا ينتظر وكيل اكتمال وكيل آخر إلا عند وجود تبعية مباشرة.

## حالة الدمج الحالية

### الموجة الحالية: Wave 1 (V23 Implementation)

| الطبقة | الحالة | الوكيل المسؤول | ملاحظات |
|---|---|---|---|
| Shared Contracts | ✅ محدّث (17 schema, V23 KPI) | 14 — Integration | kpi.ts V23 parallel flow, 180 test pass |
| Migrations | 🟡 نشط (163 migration) | 2 — Database | آخر: 0163_v23_security_search_path_hardening |
| RLS/RPC/Edge | ✅ قائم (12 Edge Function) | 3 — Security | مستقر |
| Repositories/State | ✅ قائم | 5/10 — Web/Mobile | مستقر |
| UI — Web | 🟡 نشط (14+ feature) | 5 — Web Admin | V23 UI updates in progress |
| UI — Mobile | 🟡 نشط (44+ page) | 10 — Executive Mobile | V23 dispute form updates |
| Tests — pgTAP | ✅ محدّث (67 test file) | 2 — Database | V23 tests added |
| Tests — Web | ✅ قائم (32 test) | 5 — Web Admin | مستقر |
| Tests — Flutter | ✅ قائم (29 test) | 10 — Executive Mobile | مستقر |
| Tests — Contracts | ✅ محدّث (180 test, 34 files) | 14 — Integration | V23 KPI evaluator fix |
| Docs | ✅ محدّث | 14 — Integration | MIGRATION_REGISTRY + BLOCKERS + TRACEABILITY |

---

## سجل الدمج

| # | التاريخ | الوكيل | الطبقة | الوصف | Commit |
|---|---|---|---|---|---|
| 1 | 2026-07-26 | 14 | Docs | إنشاء بنية Integration V23 | — |
| 2 | 2026-07-27 | 14 | Contracts | إصلاح kpi.test.ts V23 CONDUCT evaluator (REQ-C001) | pending |
| 3 | 2026-07-27 | 14 | Docs | تحديث BLOCKERS (BLK-0001/0003) + MIGRATION_REGISTRY | pending |
| 4 | 2026-07-27 | 14 | Docs | تحديث MERGE_QUEUE + TRACEABILITY + CROSS_AGENT_REQUESTS | pending |
| 2 | 2026-07-27 | 14 | Contracts | إصلاح kpi.test.ts V23 (CONDUCT→manager) | REQ-C001 |
| 3 | 2026-07-27 | 14 | Docs | تحديث MIGRATION_REGISTRY + BLOCKERS + integration docs | — |

---

## طابور الانتظار

> لا توجد عناصر في طابور الانتظار حالياً. سيضاف كل طلب دمج جديد هنا.
