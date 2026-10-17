# خطة إكمال النظام — للتنفيذ بواسطة وكيل (2026-10-07)

> المستودع: `D:\Coder\HR\HR_Platform_2` · الفرع: `main` · Supabase ref: `ujzzvqsodyhnnnpkoaml`
> نفّذ المراحل **بالترتيب**. كل مرحلة لها «تعريف الإنجاز». التقارير للمالك **بالعربية**.

---

## 0) قواعد إلزامية قبل أي خطوة

1. **جلسات متوازية تشترك في نفس مجلد العمل والـ index.**
   - ممنوع `git add -A` و`git commit -a` و`git reset --hard` و`git stash` على الشجرة المشتركة.
   - احفظ بمسارات صريحة فقط. الأسلم الـ commit عبر index خاص:
     ```bash
     export GIT_INDEX_FILE=.git/index-mine; git read-tree origin/main
     git add -- <مساراتك فقط>; T=$(git write-tree)
     C=$(git commit-tree "$T" -p origin/main -F msg.txt); unset GIT_INDEX_FILE
     git push origin "$C":refs/heads/main
     ```
   - ادفع فور الـ commit. افحص `git log origin/main..HEAD` قبل أي push.
   - تحقق من محتوى الـ commit بـ `git show --stat`.
2. **أرقام migrations:** افحص `ls supabase/migrations | cut -c1-4 | sort | uniq -d` قبل الإنشاء.
   - 0657 و0658 **محجوزان** لجلسة «إشعارات غير فعالة».
   - 0656 لجلسة أخرى.
   - **أول رقم حر لك: 0660**.
3. **ممنوع تعديل migration منشورة.** أي تعديل يكون في ملف جديد.
   - عند تعديل دالة منشورة: انسخ تعريف الإنتاج كاملاً (`pg_get_functiondef`) وعدّل عليه. لا تعدّل ملفاً قديماً.
4. **الإنتاج:**
   - لا تطبيق ولا قراءة على قاعدة الإنتاج إلا بعد **جملة صريحة من المالك تذكر أرقام الـ migrations وكلمة «الإنتاج»**.
   - نظام الصلاحيات قد يمنع حتى القراءة. إن حدث ذلك فتوقف واطلب من المالك.
5. **الأسرار والبيانات الشخصية:**
   - المفتاح عبر متغير بيئة مضمَّن في الأمر نفسه فقط (`SUPABASE_ACCESS_TOKEN=...`).
   - لا تطبع مفتاحاً أو اسم موظف أو رقم هاتف أو user id في أي log أو مخرج.
6. **قواعد الواجهة:**
   - كل الواجهات عربية RTL.
   - **كل القوائم الأحدث أولاً**: الاستعجال شارة على البطاقة وليس مفتاح ترتيب.
   - البطاقات ذات النص الأبيض تستخدم `BrandGradients` (في `lib/core/theme/brand_gradients.dart`) وليس `scheme.primary`.

---

## 1) قاعدة الإنتاج — بعد جملة المالك فقط

**المطلوب تطبيقه:**

| ملف | ماذا يفعل | تحقق سابق |
|---|---|---|
| 0648 | يزيل مطابقة الاسم `ilike '%يحيى%جمال%'` من دالتي الإيقاف (الحماية تبقى بالمعرّف) | تم: الفرق مع الإنتاج = حذف سطري الاسم فقط |
| 0649 | يحذف 8 سياسات `using(true)` كانت تكشف محتوى النزاعات لكل موظف، ويقفل `audit_events_partitioned` | آمن: لا migration لاحقة تلمسها |
| 0650 | يحذف `get_pending_suspensions` و`suspend_employee_for_penalty` (لوحة أُلغيت) | `drop … if exists` بلا cascade، والويب القديم لا ينكسر |
| 0659 | يمنح `performance.kpi.self_assess` بنطاق `self` لكل دور غير كامل الوصول (المديرون عالقون في «تقييم ذاتي متأخر») | اختبار 5/5، واختبارات KPI القائمة 122/122 |

**التنفيذ:** أمران منفصلان، لأن نطاقاً من 0648 إلى 0659 سيطبّق 0656 أيضاً.
```bash
SUPABASE_ACCESS_TOKEN=<المفتاح> python scripts/deploy_migrations.py --from 0648 --to 0650
SUPABASE_ACCESS_TOKEN=<المفتاح> python scripts/deploy_migrations.py --from 0659 --to 0659
```
سطر **FAIL** «untracked local migrations below remote max» متوقع حتى تُنجز المرحلة 2.

**تحقق بعد التطبيق (قراءة فقط):**
- لا سياسات `*_read` بـ `qual = true` على جداول `dispute_*` الثمانية.
- `audit_events_partitioned` وأقسامه: RLS مفعّل، ولا SELECT أو INSERT لـ `authenticated` و`anon`.
- الدالتان المحذوفتان غير موجودتين.
- `prosrc` لدالتي 0648 بلا `ilike`.
- `direct-manager` يملك `self_assess`.
- أعد فحص التلف: `select proname from pg_proc where prosrc ~ '(\?\?\?|Ø|Ù|ðŸ|â€)'` (يجب أن يكون فارغاً).

**تعريف الإنجاز:** الأربعة مسجّلة في `supabase_migrations.schema_migrations`، والفحوص كلها سليمة.

---

## 2) جعل git يطابق الإنتاج (أكبر خطر حالياً)

**الوضع:** 38 ملف migration غير محفوظة في git، و14 منها غير مسجّلة في الإنتاج أيضاً.

1. **المسجّلة في الإنتاج وغير المحفوظة** (منها: 0596، 0598، 0603–0609، 0614–0620، 0632، 0637، 0643، 0644، 0652، 0653):
   - قارن كل ملف بـ `schema_migrations.statements` في الإنتاج.
   - احفظ المطابق مع اختباره في commits مرتبة.
   - إن اختلف ملف عن المسجّل فاحفظ نسخة الإنتاج.
2. **غير المسجّلة وغير المحفوظة:** 0599، 0625–0628، 0630، 0633–0636، 0638–0641. لكل ملف:
   - هل تجاوزته migration أحدث تعيد تعريف نفس الكائنات؟ إن نعم، انقله إلى `supabase/migrations/_v23_parking/`.
   - هل كائناته موجودة في الإنتاج بنفس التعريف (طُبّق يدوياً)؟ إن نعم، سجّله فقط في `schema_migrations` بموافقة المالك.
   - هل ما زال مطلوباً؟ إن نعم، يُطبَّق بموافقة المالك بالرقم.
3. **migrations منشورة معدّلة في مجلد العمل:** 0581 و0582. راجع `git diff`:
   - إن كان التعديل مطلوباً، انقله إلى migration جديدة (0660 أو أعلى).
   - ثم أرجِع الملفين: `git checkout -- <file>`. نسّق مع الجلسة صاحبة التعديل.

**تعريف الإنجاز:**
- `git status --short supabase/migrations` فارغ (عدا ملفات الجلسة الأخرى المعلّقة خارج المجلد).
- فحص «untracked gap» في أداة النشر = PASS.

---

## 3) حفظ كود التطبيق والويب غير المحفوظ

**الوضع:**
- الموبايل: نحو 77 ملفاً (55 معدّلاً، و3 محذوفة، و19 جديدة). نسخة APK 0.13.26+43 مبنية منها.
- الويب: نحو 62 ملفاً.
- `packages`: 7 ملفات.
- `supabase/tests`: 29 ملفاً.

**المنهج:** لكل وحدة:
1. انسخ `HEAD` إلى مجلد مؤقت على C: (`git archive HEAD apps/mobile_flutter packages/design-tokens | tar -x -C <tmp>`).
2. ضع ملفات الوحدة فوقه.
3. شغّل `flutter pub get` ثم `flutter analyze` ثم `flutter test`.
4. للويب: `npm run typecheck && npm run lint && npm run test`.
5. احفظ الوحدة التي تنجح عبر الـ index الخاص، ثم ادفع.

**الوحدات المعروفة:**

| # | الوحدة | الملفات الأساسية | ملاحظة |
|---|---|---|---|
| 1 | الغرامات وصندوق الزمالة | `my_instant_penalties_page.dart` + `penalties_providers.dart` + حقول `mobile_models.dart` + `test/my_instant_penalties_page_test.dart` + `test/goldens/` | |
| 2 | الإشعارات | `mobile_notifications_page.dart` + `notificationsLimitProvider` في `mobile_providers.dart` + توقيع `deleteNotifications` في `mobile_commands.dart` | |
| 3 | التقارير اليومية | `daily_reports_feed_page.dart` + `isClinicStaff` في `access_context.dart` | |
| 4 | الطلبات | `team_requests_page`، و`mobile_requests_page`، و`mobile_request_detail_page`، و`mobile_action_inbox_page`، و`request_display/decision_sheet/list_widgets` + `test/features/requests/team_requests_order_test.dart` | ملك «إشعارات غير فعالة»: نسّق معها |
| 5 | ألوان البطاقات والشارات | `lib/core/theme/brand_gradients.dart` + `employee_home_page`، و`executive_reports_page`، و`mobile_attendance_page`، و`mobile_profile_page`، و`login_page` + `workspace_scaffold`، و`executive_workspace` | شارة «99+» بـ `TextDirection.ltr` |
| 6 | الويب | الصفحات المعدّلة + حذف helpdesk/knowledge/learning | تأكد أن المسارات والقوائم لا تشير للمحذوف |

إن خلط ملفٌ أكثر من وحدة، فاحفظ الوحدات معاً ولا تقسّم الملف يدوياً.

**تعريف الإنجاز:**
- `git status --short apps packages` فارغ أو يقتصر على عمل جلسة أخرى جارٍ.
- CI أخضر على `main`.

---

## 4) باقي تحسينات الشاشات (الموبايل أولاً)

**أدوات الفحص البصري** (خارج المستودع، تُشغَّل من `apps/mobile_flutter`):
- `D:/tmp/w/screens_visual_test.dart` لأحادي الصفحة: `--dart-define=ONLY=...`.
- `D:/tmp/w/workspace_visual_test.dart` لمساحات الموظف والمدير: `--dart-define=WS=employee|manager` و`SCENES=...`. الوضع الداكن افتراضي.
- `D:/tmp/w/executive_visual_test.dart` للمدير التنفيذي. غيّر `AppTheme.light()` إلى `dark` كما في الملف السابق.

**الشاشات غير المراجعة:**
- شاشات المدير التنفيذي.
- تبويبا «غرامات الموظفين» و«صندوق الزمالة».
- تفاصيل صفحة الحضور (البصمة، المأمورية، الورديات).
- ورقة تفاصيل الإشعار.
- صفحات لوحة الويب الرئيسية.

**ما تبحث عنه:**
- تباين ضعيف في الوضع الداكن.
- نصوص إنجليزية خام (status codes).
- أوقات تُعرض بـ UTC، والصحيح `.toLocal()`.
- علامات تنقلب في RTL مثل «+99».
- قوائم ليست الأحدث أولاً.
- أزرار لإجراءات يرفضها الخادم.
- زر عائم يغطي المحتوى.
- طباعة PII في `debugPrint` غير محمي بـ `kDebugMode`.

**لا تلمس** ما تعمل عليه جلسة «إشعارات غير فعالة»:
- صفحات الطلبات.
- «شهري في لمحة».
- إعدادات الإشعارات.
- الكشف الشهري و`employee_profile`.
- دوال `set/clear_employee_attendance_day_admin` و`submit_employee_day_mark` و`get_employee_monthly_attendance_statement` و`get_employee_360`.

**تعريف الإنجاز:**
- صور قبل وبعد لكل شاشة.
- `flutter analyze` بلا جديد.
- `flutter test` كله ناجح.

---

## 5) الإصدار

1. **التطبيق 0.13.27+44:** بعد المرحلة 3، ويُستحسن البناء من `HEAD` النظيف.
   - انسخ الملفات المستثناة من git: `android/keystore.properties`، و`android/app/release-keystore-v2.jks`، و`android/local.properties`، و`dart_define/production.json`.
   ```bash
   flutter build apk --release --dart-define-from-file=dart_define/production.json --build-name 0.13.27 --build-number 44
   ```
   - تحقق من الإصدار: `C:/Android/Sdk/build-tools/36.0.0/aapt.exe dump badging <apk>` يجب أن يُظهر `versionCode='44'`.
   - تحقق من التوقيع: `python D:/tmp/w/apk_cert.py <apk>` يجب أن يطابق `2D:4C:CB:…`. أي مفتاح آخر يجعل أندرويد يرفض التحديث.
   - انسخه إلى `C:\Users\Elhamd\Desktop\AhlaShabab-0.13.27+44.apk`.
2. **الويب:** من `git archive HEAD` في مجلد مؤقت، ثم `npx vercel --prod --yes` بموافقة المالك. تحقق بعدها من نصوص جديدة في الـ chunks الحية.
3. **ترتيب النشر:** قاعدة البيانات ثم الويب ثم التطبيق.

---

## 6) أمان وتنظيف (بعضها إجراء للمالك)

- [ ] **المالك:** غيّر مفتاح Supabase (`sbp_…`). هو مكتوب كنص صريح في نحو 10 سكربتات تحت `scratch/` (مستثناة من git). بعد التغيير احذف المفتاح من السكربتات واستعمل متغير البيئة.
- [ ] احذف الفرع `rescue/orphaned-security-fixes`، فكلا الـ commit فيه (abe412c و42b2ce3) موجودان في `main` الآن.
- [ ] تحذير `unused_import` في `monthly_attendance_statement_page.dart` (ملف الجلسة الأخرى).
- [ ] Docker Desktop يتوقف أحياناً. إعادة تشغيله: `cmd //c start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"`، وانتظر حتى يصبح `supabase_db_…` في حالة `healthy`.

## 7) قرارات معلّقة عند المالك

- [ ] جملة تطبيق 0648 و0649 و0650 و0659 على الإنتاج.
- [ ] الموافقة على 0657 و0658 (جلسة «إشعارات غير فعالة»).
- [ ] مصير الـ 14 migration القديمة (المرحلة 2.2).
- [ ] نشر الويب.
- [ ] جعل الإصدار 43 حداً أدنى إلزامياً للتطبيق.
