# مواصفة Payroll Formula DSL — أحلى شباب HR
**النسخة:** 1.0 | **التاريخ:** 2026-07-31 | **الحالة:** للموافقة القانونية/المالية

---

## 1. الهدف
لغة تعبيرية آمنة (DSL) محصورة في JSON، **بدون eval/exec**، تُعبَّر عن مكوّنات الراتب والحسومات والضرائب والبدلات، وتُنفَّذ عبر مفسّر PL/pgSQL آمن.

## 2. لماذا DSL وليس SQL/Hardcode؟
| البديل | العيب |
|--------|-------|
| PL/pgSQL hardcoded | يتطلب migration لكل تغيير قانوني — بطيء وعالي المخاطر |
| eval / JavaScript | ثغرة RCE واضحة — **ممنوع تماماً** |
| **JSON DSL** | ✅ مصادقة عبر JSON Schema + تدقيق آلي + تغيير config فقط |

---

## 3. البنية العامة
```json
{
  "version": "1.0",
  "jurisdiction": "EG",
  "effective_from": "2026-01-01",
  "components": [ ... ],
  "statutory_rules": [ ... ]
}
```

---

## 4. أنواع العقد الأساسية (Nodes)

### 4.1 `fixed_amount`
```json
{ "id": "base_salary", "type": "fixed_amount", "amount": 8000.00, "currency": "EGP" }
```
**القيود:** `amount >= 0`

### 4.2 `percentage_of_basic`
```json
{ "id": "housing", "type": "percentage_of_basic", "percentage": 25, "cap_amount": 2000.00 }
```
**القيود:** `percentage ∈ [0, 100]`؛ `cap_amount` اختياري لكن موصى به

### 4.3 `attendance_deduction`
```json
{
  "id": "unpaid_leave",
  "type": "attendance_deduction",
  "rule": "per_unauthorized_day",
  "base_divisor": 30
}
```
**القيود:** المصدر فقط `attendance_exceptions.status = 'approved'`؛ يمنع تجاوز صافي الراتب

### 4.4 `loan_installment`
```json
{ "id": "personal_loan", "type": "loan_installment", "loan_id_field": "loan_id", "max_percentage_of_net": 25 }
```
**القيود:** يقرأ من `loan_installments` فقط؛ لا يتجاوز الرصيد أو النسبة القصوى

### 4.5 `tiered_tax` — شرائح الضريبة (مصر 2026)
```json
{
  "id": "egypt_income_tax",
  "type": "tiered_tax",
  "jurisdiction": "EG",
  "period": "annual",
  "brackets": [
    { "up_to": 30000, "rate": 0 },
    { "up_to": 45000, "rate": 15 },
    { "up_to": 60000, "rate": 20 },
    { "up_to": 200000, "rate": 25 },
    { "up_to": 400000, "rate": 30 },
    { "up_to": 1200000, "rate": 35 },
    { "up_to": null, "rate": 40 }
  ]
}
```
**القيد الأمني:** `up_to: null` = فئة مفتوحة؛ الشرائح مرتبة تصاعدياً حصراً

### 4.6 `conditional`
```json
{
  "id": "remote_incentive",
  "type": "conditional",
  "condition": {
    "op": "and",
    "all": [
      { "op": "field_equals", "field": "work_location", "value": "remote" },
      { "op": "in_set", "field": "grade", "values": ["senior", "lead"] }
    ]
  },
  "then": { "type": "fixed_amount", "amount": 500 },
  "else": { "type": "fixed_amount", "amount": 0 }
}
```
**العمليات المسموحة فقط:** `and`, `or`, `not`, `field_equals`, `in_set`, `greater_than`, `less_than`

---

## 5. قواعد الأمان الإلزامية

| القاعدة | التنفيذ |
|--------|---------|
| **لا eval** | المفسّر PL/pgSQL يقرأ JSON عبر `jsonb_path_query` — يشغل فقط أنواع العقد المعروفة |
| **لا وصول مباشر للجداول** | مصادر مغلقة: `AVAILABLE_SOURCES = ['contract','attendance','loans','benefits']` |
| **Immutable snapshot** | عند `payroll_runs.status = 'calculated'`، تُخزَّن المدخلات في `payroll_runs.input_snapshot` (JSONB) للتدقيق |
| **Validation صارم** | `jsonschema` validation قبل الحفظ + dry-run إجباري على 10 موظفين عشوائيين |
| **Segregation of duties** | `payroll.formula.manage` ≠ `payroll.run.approve` — شخصان مختلفان إلزامياً |

---

## 6. جداول SQL المقترحة (Migration مستقبلية)

```sql
create table if not exists public.payroll_formula_templates (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_ar text not null,
  jurisdiction text not null default 'EG',
  version integer not null default 1,
  spec jsonb not null,           -- DSL JSON — يُفسَّر آمنًا فقط، لا eval
  active boolean not null default false,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique(code, version)
);

comment on column public.payroll_formula_templates.spec is
  'DSL JSON — لا eval؛ يُفسَّر آمنًا عبر payroll_formula_interpreter() فقط';
```

---

## 7. خطة التنفيذ — 4 أسابيع

| الأسبوع | العمل |
|---------|------|
| **1** | جداول + `payroll_formula_interpreter()` PL/pgSQL + unit tests لكل نوع عقدة |
| **2** | `pg_jsonschema` validation + dry-run snapshots + تسجيل التدقيق |
| **3** | PDF Payslips (Edge) + إشعارات + واجهة Finance موحّدة `/admin/finance` |
| **4** | RBAC segregation + تقارير شهرية مقارنة + سوابق تدقيق + أرشفة سنوية |

---

## 8. ملاحظة قانونية
> الصيغ الضريبية أعلاه **مرجعية** وتخضع للتحديث السنوي لقوانين مصر.  
> يجب المراجعة إلزامياً من القسم القانوني/المالي **قبل أي payroll run فعلي**.  
> كل تعديل يُنشئ `version` جديدة مع سبب التغيير والموافقة المُسجلة.

**انتهت المواصفة.**
