# إصلاح staging — مطابقة الباك إند مع مجلد HR_Platform_2

## الخلاصة أولاً (مهم)

نشرتَ الدوال من مجلد **`HR_Platform`** (القديم)، بينما المصدر الصحيح هو
**`HR_Platform_2`** (المتصل بالويب والموبايل، وفيه 48 migration والدوال الأحدث).

نتيجة ذلك، الدوال على staging لا تطابق ما يستدعيه التطبيق فعلاً:

| يستدعيه التطبيق | موجود على staging الآن؟ | الأثر |
|---|---|---|
| `identifier-sign-in` (تسجيل الدخول — ويب + موبايل) | ❌ (يوجد `resolve-login-identifier` بدلاً منه) | **تسجيل الدخول معطّل** |
| `admin-create-employee` (إنشاء موظف — ويب) | ❌ (يوجد `admin-create-user` بدلاً منه) | **إنشاء الموظف معطّل** |
| `webauthn-challenge` | ✅ | يعمل |
| `passkey-register` | ✅ | يعمل |
| `verify-attendance-punch` | ✅ | يعمل |

لذلك يجب إعادة النشر من مجلد `HR_Platform_2`.

---

## 1) تأكد أنك في المجلد الصحيح

كل الأوامر التالية تُشغَّل من: `D:\Coder\HR\HR_Platform_2` (وليس `HR_Platform`).

```powershell
cd D:\Coder\HR\HR_Platform_2

# تحقّق أن أسماء الدوال هنا هي الصحيحة (يجب أن ترى admin-create-employee و identifier-sign-in)
Get-ChildItem supabase/functions -Directory | Select-Object Name
```

يجب أن تظهر 9 مجلدات + `_shared`:
`admin-create-employee, identifier-sign-in, integration-outbox-worker, notification-dispatcher, passkey-register, retention-cleanup, scheduled-report-runner, verify-attendance-punch, webauthn-challenge`

الربط بالمشروع (إن لم يكن مربوطاً من هذا المجلد):

```powershell
npx supabase link --project-ref ujzzvqsodyhnnnpkoaml
```

---

## 2) ادفع أي migrations ناقصة (الأهم)

الدوال المختلفة تلمّح إلى أن قاعدة staging قد تكون من نسخة أقدم. ادفع migrations هذا المجلد:

```powershell
# معاينة الفرق أولاً
npx supabase db push --dry-run

# ثم التنفيذ الفعلي
npx supabase db push
```

> إذا ظهرت رسالة تعارض تاريخ الهجرات (remote history mismatch) لأن staging طُبّق عليه
> نسخة قديمة بأسماء مختلفة، راجع القسم "معالجة تعارض تاريخ الهجرات" أسفل الملف.

---

## 3) أعد نشر الدوال الصحيحة الـ 9 من هذا المجلد

```powershell
npx supabase functions deploy --project-ref ujzzvqsodyhnnnpkoaml
```

هذا سينشر (ويحدّث) الدوال الصحيحة، ويُضيف `identifier-sign-in` و`admin-create-employee`
المفقودتين — وبذلك يعود تسجيل الدخول وإنشاء الموظف للعمل.

---

## 4) احذف الدوال القديمة الزائدة (اختياري لكن موصى به)

هذه الدوال موجودة على staging لكنها **ليست** في `HR_Platform_2`، وقد تسبّب لبساً أو
استدعاءات خاطئة. احذفها بعد التأكد أن لا شيء في الكود الحالي يستدعيها:

```powershell
npx supabase functions delete resolve-login-identifier   --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions delete admin-create-user          --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions delete complete-initial-password  --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions delete process-request-sla        --project-ref ujzzvqsodyhnnnpkoaml
```

> تحذير: إن كان أي من `complete-initial-password` أو `process-request-sla` جزءاً من
> تدفّق مقصود في نسخة أحدث لديك، لا تحذفه. الحذف عكسي (يمكن إعادة نشره)، لكن تأكّد أولاً.
> الأساسي هنا هو الخطوة 3 (إعادة النشر)، أما الحذف فتنظيف.

---

## 5) التحقق النهائي

```powershell
npx supabase functions list --project-ref ujzzvqsodyhnnnpkoaml
```

يجب أن ترى الآن — على الأقل — هذه الدوال `ACTIVE`:
`admin-create-employee, identifier-sign-in, webauthn-challenge, passkey-register,
verify-attendance-punch` (بالإضافة إلى notification-dispatcher / retention-cleanup /
scheduled-report-runner / integration-outbox-worker).

اختبار حيّ:
1. افتح الويب `apps/admin_web` (`npm run dev`) وسجّل الدخول بحساب موجود → يجب أن ينجح الآن.
2. جرّب إنشاء موظف من شاشة CreateEmployee → يجب أن ينجح.
3. من الموبايل `apps/mobile_flutter/run_staging.ps1` سجّل الدخول وجرّب البصمة.

---

## معالجة تعارض تاريخ الهجرات (إن ظهر في الخطوة 2)

إذا رفض `db push` بسبب أن staging يحمل تاريخ هجرات من المجلد القديم:

```powershell
# اعرض الفرق بين المحلي والبعيد
npx supabase migration list --project-ref ujzzvqsodyhnnnpkoaml
```

- إن كانت staging **بيئة اختبار يمكن إعادة بنائها** ولا تحوي بيانات مهمة، فأسهل حل هو
  إعادة ضبطها لتطابق هذا المجلد. **حذّر: هذا يمسح بيانات staging.** لا تفعله على production:
  ```powershell
  # يعيد بناء قاعدة staging من migrations هذا المجلد (يمسح البيانات الحالية)
  npx supabase db reset --linked
  ```
- إن كانت staging تحوي بيانات تريد الاحتفاظ بها، لا تعمل reset. بدلاً من ذلك
  أرسل لي مخرجات `migration list` وسأساعدك في مطابقة التاريخ يدوياً
  (عبر `migration repair`) دون فقد بيانات.

---

## الترتيب المختصر

```powershell
cd D:\Coder\HR\HR_Platform_2
npx supabase link --project-ref ujzzvqsodyhnnnpkoaml
npx supabase db push
npx supabase functions deploy --project-ref ujzzvqsodyhnnnpkoaml
# تنظيف اختياري:
npx supabase functions delete resolve-login-identifier --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions delete admin-create-user --project-ref ujzzvqsodyhnnnpkoaml
npx supabase functions list --project-ref ujzzvqsodyhnnnpkoaml
```
