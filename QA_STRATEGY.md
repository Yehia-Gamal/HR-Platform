# استراتيجية ضمان الجودة — أحلى شباب HR V23

> هذا المستند يحدد خطة الاختبار الشاملة، خط الأساس الحالي، الفجوات، والأهداف لكل طبقة.

## 1. الوضع الحالي (Baseline)

| الطبقة | ملفات | اختبارات/تأكيدات | التقييم |
|---|---|---|---|
| Web (Vitest) | 8 | 26 | ⚠️ ضعيف — 12/14 feature بدون اختبار |
| العقود المشتركة (Vitest) | 17 | 90 | ✅ تغطية كاملة على مستوى الملف |
| Flutter | 6 | 30 | ⚠️ Models فقط — لا widget/integration |
| pgTAP (قاعدة البيانات) | 61 | 763 | ✅ الأقوى — بعض domains هيكلية فقط |
| E2E | 0 | 0 | 🔴 غائبة تماماً |
| اختبارات الحمل | 0 | 0 | 🔴 غائبة تماماً |
| **الإجمالي** | **92** | **909** | — |

## 2. استراتيجية الاختبار

### 2.1 الهرم المعتمد

```
        ╱ E2E (Playwright) ╲        ← أقل عدداً، أعلى ثقة
       ╱  Integration Tests  ╲
      ╱   Component Tests     ╲
     ╱    Unit Tests            ╲
    ╱     Contract Tests          ╲
   ╱      pgTAP DB Tests           ╲  ← أكثر عدداً، أسرع تنفيذاً
```

### 2.2 طبقات الاختبار

| الطبقة | الأداة | الهدف | CI Gate |
|---|---|---|---|
| Unit/Component (Web) | Vitest + Testing Library | منطق العرض والمكونات | ✅ كل PR |
| Unit (Flutter) | flutter_test | Models + Providers + Widgets | ✅ كل PR |
| Contract | Vitest | Zod schemas + API contracts | ✅ كل PR |
| Database | pgTAP | RLS + RPCs + Triggers + Constraints | ✅ كل PR |
| Security Static | check-no-secrets + validate-foundation | أسرار + SERVICE_ROLE | ✅ كل PR |
| Security Runtime | edge-smoke-tests.sh | Auth + CORS + leak detection | ✅ كل PR (جديد) |
| E2E | Playwright | مسارات المستخدم الحرجة | ✅ كل PR (جديد) |
| Load | k6 | أداء تحت الضغط | 📋 يدوي / Release gate |
| Visual | Percy/Chromatic | تغيرات بصرية غير مقصودة | 📋 مستقبلي |

### 2.3 أهداف التغطية (V23)

| المجال | الهدف | الأولوية |
|---|---|---|
| Auth flow (login/password) | E2E كامل | P0 |
| Employee CRUD | Unit + E2E | P0 |
| Attendance punch | Unit + pgTAP negative + E2E | P0 |
| Leave/Request workflow | pgTAP + E2E | P0 |
| KPI cycle | pgTAP + Component | P1 |
| Disputes | pgTAP + Component | P1 |
| Live location | pgTAP (موجود) + Security | P1 |
| Dashboard/Reports | Component | P2 |
| Admin management pages | Component | P2 |

## 3. استراتيجية بيانات الاختبار

### 3.1 بيئات الاختبار

| البيئة | البيانات | الاستخدام |
|---|---|---|
| CI (pgTAP) | fixtures داخل كل ملف اختبار | اختبارات DB آلية |
| CI (Vitest) | mocks + Zod factories | اختبارات مكونات |
| CI (E2E) | `VITE_ENABLE_DEV_MOCKS=true` | مسارات واجهة بدون Supabase |
| Staging | `scripts/seed_demo.sql` | اختبارات يدوية + smoke |
| Local | `supabase db reset` + seed | تطوير محلي |

### 3.2 Personas المعتمدة للاختبار

| الشخصية | الدور | الاستخدام |
|---|---|---|
| admin@ahlashabab.org | Main Admin (السكرتير التنفيذي) | إدارة النظام |
| hr@ahlashabab.org | HR Specialist | عمليات الموارد البشرية |
| manager@ahlashabab.org | Direct Manager (مدير تشغيل) | فريق + طلبات |
| employee@ahlashabab.org | Employee | خدمة ذاتية |
| executive@ahlashabab.org | Executive Director | قرارات + موقع + تقارير |

### 3.3 قواعد بيانات الاختبار

- **لا PII حقيقية** في أي بيئة اختبار.
- كلمات المرور الافتراضية للاختبار: `Test@2026!` (ثابتة في staging فقط).
- بيانات seed تستخدم أسماء وهمية عربية.
- كل ملف pgTAP ينشئ fixtures خاصة به ويحذفها في `finish()`.

## 4. معايير بوابة الإصدار (Release Gate)

### P0 — يجب تحقيقها قبل أي إصدار

- [ ] صفر P0 bugs مفتوحة
- [ ] `npm run check:all` ناجح (typecheck + test + build + secrets + foundation)
- [ ] `supabase db reset && supabase test db` ناجح (مرتين — idempotency)
- [ ] `flutter analyze --no-fatal-infos` نظيف
- [ ] `flutter test` كل الاختبارات ناجحة
- [ ] لا تكرار في أرقام Migrations
- [ ] لا أسرار في الكود المصدري
- [ ] Edge smoke tests ناجحة

### P1 — يجب تحقيقها قبل إصدار Production

- [ ] E2E tests للمسارات الحرجة ناجحة
- [ ] Staging soak (24 ساعة بدون أخطاء حرجة)
- [ ] اختبار على Android حقيقي (Samsung + آخر)
- [ ] Android 13/14/15
- [ ] GPS off/on
- [ ] Notification denied
- [ ] Foreground/background/terminated/locked
- [ ] نسخة احتياطية مؤكدة لقاعدة البيانات
- [ ] خطة Rollback موثقة ومختبرة

### P2 — مرغوبة

- [ ] Load test يمر عند 2x الحمل المتوقع
- [ ] 3x burst test لا يسبب انهياراً
- [ ] مراقبة ما بعد الإطلاق مهيأة

## 5. مصفوفة أجهزة Android

| الجهاز | Android | GPS | Notifications | الحالة |
|---|---|---|---|---|
| Samsung Galaxy | 13 | On | Allowed | Foreground |
| Samsung Galaxy | 14 | Off | Allowed | Background |
| Samsung Galaxy | 15 | On | Denied | Terminated |
| Vendor آخر | 13 | On | Allowed | Locked |
| Vendor آخر | 14 | Off | Denied | Foreground |
| Vendor آخر | 15 | On | Allowed | Background |

## 6. سيناريوهات اختبار الحمل

| السيناريو | VUs | المدة | المعيار |
|---|---|---|---|
| حمل عادي (expected peak) | 50 | 5 دقائق | p95 < 500ms |
| ضعف الحمل (2x) | 100 | 5 دقائق | p95 < 1000ms |
| انفجار (3x burst) | 150 | 2 دقيقة | لا انهيار + recovery < 30s |
| حضور متزامن | 80 | 3 دقائق | p95 < 800ms |
| تقرير شهري | 20 | 3 دقائق | p95 < 3000ms |
| نشر لجميع الموظفين | 10 | 1 دقيقة | delivery > 95% |

## 7. خطة التنفيذ

### Wave 0 (الآن)
- [x] Security baseline — فحص شامل ✅
- [x] Contract review — 90 اختبار عقد ✅
- [x] Test data strategy — هذا المستند ✅
- [x] CODEOWNERS + dependabot ✅
- [x] Release gate script ✅

### Wave 1-2
- [ ] Playwright E2E infrastructure + auth flow test
- [ ] k6 load test infrastructure + attendance scenario
- [ ] Web component tests لأهم 5 features
- [ ] Edge smoke tests في CI

### Wave 3-5
- [ ] E2E tests لكل مسار حرج
- [ ] Load test scenarios كاملة
- [ ] Flutter widget tests
- [ ] pgTAP tests للـ domains الناقصة

### Wave 6
- [ ] Full load test suite
- [ ] Security penetration testing
- [ ] Android device matrix testing
- [ ] Staging soak test

### Wave 7
- [ ] Release gate verification
- [ ] Sign-off
