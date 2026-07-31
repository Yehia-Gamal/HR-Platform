# Migration Registry — أحلى شباب HR

> سجل شامل لجميع ملفات الترحيل في `supabase/migrations/`.
> آخر تحديث: 2026-07-30 — إعادة تأهيل المرحلة 0 (الاستقرار المؤسسي).

## الإحصائيات الفعلية الحالية

| العنصر | العدد |
|---|---|
| إجمالي الملفات `.sql` المرقمة | 233: 0001–0231 + 0232 + 0233 + 0234 (يشمل placeholders مرقمة) |
| تكرارات نشطة | ✅ لا شيء |
| فجوات | ✅ لا شيء (جسور موثقة: 0119, 0122, 0194, 0219) |
| ملفات مركونة في `_v23_parking/` | ✅ يجب أن تكون فارغة — إن وُجدت تُعاد جدوَلتها عبر Integration Lead |

## السياسة الإلزامية — تجميد الترقيم (Zero-Renumber)

> 🔒 **ممنوع منعًا باتًا** إعادة استخدام أو إعادة ترقيم أي migration سبق دفعه إلى Staging/Production.
> **الترقيم تسلسلي جزافي (monotonic)**: كل ملف جديد يأخذ الرقم التالي الفارغ فقط.

| القاعدة | الإجراء الإلزامي |
|---|---|
| رقم migration جديد | 1) أنشئ الملف في `_v23_parking/NNNN_description.sql`. 2) Integration Lead يتأكد من `npm run check:migrations`. 3) يمنح الرقم التالي المتاح فوراً. |
| اكتشاف تكرار | فشل تلقائي في `check:migrations` + `release-gate`. لا يُسمح بأي commit. |
| فجوة في التسلسل | جسر no-op `[NNNN]_bridge_placeholder.sql` أو إغلاق بالترحيل نفسه إن لم يُدفع بعد. |
| تعديل migration مدفوع | ❌ ممنوع. أنشئ `NNNN_fix_<name>.sql` بترقيم جديد. |
| فحص السلامة | `node scripts/check-migrations-integrity.mjs && node scripts/generate-migrations-manifest.mjs` |

## الأدوات المؤسسية الجديدة (2026-07-30)

| السكربت | الدور |
|---|---|
| `scripts/check-migrations-integrity.mjs` | يكشف التكرار + الفجوات + placeholder غير موثق. مدمج في `check:all`. |
| `scripts/generate-migrations-manifest.mjs` | يولّد SHA-256 manifest لكل ملف (كشف إعادة كتابة). → `supabase/.temp/migrations-manifest.json` |

## الجسور الموثقة — لا تُحذف

| الرقم | الملف | السبب المختصر |
|---|---|---|
| 0119 | `0119_bridge_placeholder.sql` | سد فجوة فقدت أثناء إعادة ترقيم سابقة؛ 0120→0126 دفعت لـ Staging. |
| 0122 | `0122_bridge_placeholder.sql` | سد فجوة بين 0121→0123. |
| 0194 | `0194_placeholder.sql` | محفوظ تاريخياً لسلامة التسلسل. |
| 0219 | `0219_placeholder_sequence_fix.sql` | محفوظ تاريخياً لسلامة التسلسل. |
| 0231 | `0231_bridge_placeholder.sql` | سد فجوة من reset خارجي — 0232→0234 موجودة بالفعل. |
| 0232 | `0232_bridge_placeholder.sql` | سد فجوة من reset خارجي — 0233→0234 موجودة بالفعل. |

## العمليات الحرجة ليوم 2026-07-30

| # | الملف | الغرض |
|---|---|---|
| 0233 | `0233_critical_cron_consolidation.sql` | جدولة موحدة idempotent للمهام الحرجة + فحص صحي يومي + تنبيهات `system_alerts` عند الفقد. |
| 0234 | `0234_revoke_remaining_internal_rpcs.sql` | (موجود) التشديد الأمني على RPC الداخلية. |

---

> ✅ **الحالة:** سلسلة متصلة — 0001 → 0234 — بلا تكرار ولا فجوات نشطة.
