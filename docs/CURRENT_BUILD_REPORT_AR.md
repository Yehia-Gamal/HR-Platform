# تقرير البناء الحالي — Ahla Shabab Management OS V8 Build 0.10.0

**تاريخ البناء:** 13 يوليو 2026  
**الطبيعة:** مشروع موحّد واحد دون مشاريع موازية أو مجلدات Patch.  
**التصنيف:** Staging Candidate — ليس Production Release حتى اجتياز بوابات التشغيل والأجهزة الفعلية.

## هدف الإصدار

Build 0.10.0 هو إصدار تحسين تجربة الاستخدام والهوية البصرية. تم تطوير الشاشات داخل مشروع Build 0.9 نفسه، مع الاستفادة من الملف المرجعي المرفوع في فكرتين فقط: تسجيل الدخول بمعرّف متعدد، وتحسين تصنيف الشاشات؛ ولم يتم نسخ واجهاته أو Migrations القديمة.

## تحسينات React Web

- App Shell احترافي ثابت وقابل للطي.
- Sidebar مجمعة حسب المجالات بدل عشرات التبويبات الأفقية.
- إخفاء عناصر التنقل التي لا يملك المستخدم صلاحيتها.
- Workspace Switcher لمن يملك أكثر من مساحة عمل.
- Command Search سريع للوصول إلى الوحدات.
- Breadcrumbs وعنوان الصفحة الحالية داخل الشريط العلوي.
- Light/Dark Mode محفوظ محليًا، مع احترام تفضيل النظام.
- Header متجاوب، قائمة موبايل، Profile chip، وإشعارات.
- Login جديدة بهوية مؤسسية ورسائل أمن وخصوصية واضحة.
- Dashboards مستقلة لـHR والإدارة الرئيسية، مع Hero وKPIs وأولويات ونبض تشغيلي.
- Metric Cards وحالات Status موحدة.
- Filter bars، جداول محسنة، Sticky headers وMobile record cards.
- Empty/Loading/Error states متناسقة.
- Reduced Motion ودعم RTL واستجابة للشاشات الصغيرة.

## تحسينات Flutter

- Theme موحد أكثر احترافية مع Light/Dark وDesign Tokens.
- Workspace Scaffold جديد وتنقل واضح حسب الدور.
- الصفحة اليومية للموظف تعرض الحضور والوردية والطلبات والمهام والقرارات بدل المعلومات التقنية.
- الصفحة الرئيسية للمدير تعرض حالة الفريق والطلبات والتقييمات والأولويات.
- الصفحة التنفيذية تعرض الوارد والقرارات والمخاطر والتقارير، دون حضور شخصي.
- إخفاء الوجهات غير المسموح بها بدل عرض صفحات فارغة تعتمد على RLS فقط.
- Widgets موحدة للبطاقات والحالات والإجراءات السريعة.

## تسجيل الدخول متعدد المعرّفات

- البريد أو الهاتف أو كود الموظف.
- Edge Function باسم `identifier-sign-in`.
- عدم كشف وجود الحساب من عدمه برسائل مختلفة.
- Rate Limit على IP والمعرّف.
- تخزين Pepper/HMAC hashes فقط في سجل المحاولات، وليس المعرّف أو IP الخام.
- Migration منفصلة لسجل المحاولات مع منع وصول anon/authenticated المباشر.

## الحوكمة والإصدار

- Migration 0040 تنشر بيانات Build 0.10.0 إلى Release Policies.
- Development وStaging تحتاجان Build 10، بينما Production يظل حدّه الأدنى Build 9 إلى أن ينجح Staging.
- تحديث اختياري وليس Force Update قبل اجتياز الأجهزة الفعلية.

## حجم المشروع

- 48 Migration متسلسلة (0001→0048؛ منها 0041–0042 لمساحات الموبايل، 0043 إصلاح Runtime لصلاحية SLA، 0044 مقابلات/عروض/تعيين التوظيف، 0045 إصلاح Runtime لمنح صلاحيات الجداول للدور `authenticated`/`anon` مع الحفاظ على الجداول الخادمية، 0046 كشف الموقع المزيّف وحارس الانتقال المستحيل للحضور، 0047 الاستحقاق الشهري للإجازات وجدولة pg_cron، 0048 إصلاح search_path لـ pgcrypto/digest للنشر المُدار).
- 30 ملف اختبار SQL/pgTAP (0001→0030؛ منها 0027 مصفوفة Persona RLS الفعلية، 0028 عقد التوظيف، 0029 دورة حياة Break-glass الفعلية، 0030 الاستحقاق الشهري للإجازات).
- 9 Edge Functions قابلة للنشر + مجلد `_shared` مشترك.
- 61 ملف Dart و205 Class.
- 75 ملف TypeScript/TSX داخل Web.
- 33 اختبار TypeScript/React ناجحًا عبر 11 ملف اختبار (19 عقود مشتركة + 14 ويب).

## نتائج الفحوصات الحالية

| الفحص | النتيجة |
|---|---|
| TypeScript strict | ناجح |
| Shared Contract Tests | 19/19 (7 ملفات) |
| React/Admin-Web Tests | 14/14 (4 ملفات) |
| React Production Build | ناجح |
| npm Production Audit | 0 ثغرات معلنة |
| Secret Scan | ناجح |
| Dart Source Integrity | 61 ملفًا، 205 Class |
| Migration Sequence | 48/48 |
| Foundation Structure | ناجح |
| Supabase `db reset` (محلي) | ✅ ناجح مرتين متتاليتين (0001→0048 + Seeds) |
| Supabase `test db` (pgTAP) | ✅ PASS — Files=30, Tests=341, صفر فشل، مرتين متتاليتين |
| Persona RLS Runtime (0027) | ✅ 23/23 فحص فعلي (بعد إصلاح 0045) |
| ZIP Integrity | يُفحص عند التغليف |

## القيود التي لم يتم الادعاء بتجاوزها

- `supabase db reset` + `supabase test db` نجحا مرتين متتاليتين محليًا فعليًا (انظر `docs/runtime-evidence/02_DATABASE_RESET_AND_PGTAP.md`): **Result: PASS — Files=30, Tests=341، صفر فشل**. pgTAP كان قد كشف عيوب Runtime حقيقية عولجت عبر Migration 0043 (منح service_role لمعالج SLA) وMigration 0045 (منح صلاحيات الجداول للدور `authenticated`/`anon` لتفعيل RLS مع الإبقاء على الجداول الخادمية بلا كتابة مباشرة)، بالإضافة إلى إصلاح توافق أدوات pgTAP في 5 ملفات اختبار. كما أُضيف Migration 0046 (كشف الموقع المزيّف + حارس الانتقال المستحيل) وTest 0029 (Break-glass runtime)، وعُدِّل توقيع اختبار 0001 ليطابق توقيع `record_attendance_event` الموسّع (10 معاملات). وأُضيف Migration 0047 (الاستحقاق الشهري للإجازات + جدولة pg_cron) وTest 0030 (يتحقق من الاستحقاق: الحقل، الدالة، حماية service_role، صحة الحساب، الحد السنوي، وidempotency)، وMigration 0048 (search_path لـ pgcrypto/digest لإصلاح النشر المُدار) — وأُعيد التحقق: reset ×2 + pgTAP ×2 = **Files=30, Tests=341 PASS**.
- `flutter analyze` و`flutter test` نجحا (0 مشاكل، **20/20**)، و**Debug APK مبني بنجاح** (Exit 0، ~238MB) بعد إصلاح Gradle cache وضبط JDK 21 (انظر `07_FLUTTER_ANALYZE_TEST_BUILD.md`).
- Passkey وGPS والكاميرا وPush تحتاج أجهزة فعلية.
- Chromium Headless داخل الحاوية تعذر بسبب قيود DBus/Kernel، لذلك لم يتم الادعاء باختبار Visual Screenshot آلي.
- يلزم Human Visual QA على Chrome وAndroid وiOS بأحجام وأدوار مختلفة.

## الحكم

Build 0.10.0 يحول الواجهات من Foundation/Wireframe إلى تجربة مؤسسية منظمة وقابلة للاستخدام في Staging. لا يزال اعتماد Production مرتبطًا بتشغيل قاعدة البيانات وFlutter فعليًا، واختبارات الأشخاص والأجهزة وVisual QA والتوقيع والنسخ الاحتياطي والاستعادة.
