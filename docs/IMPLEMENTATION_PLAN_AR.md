# خطة التنفيذ الحالية بعد Build 0.10.0

يُستكمل العمل داخل المشروع نفسه وفق Vertical Slices، ولا تُنشأ نسخة مشروع موازية.

## المنفذ

- الهوية والصلاحيات والـWorkspaces.
- إنشاء الموظف والحساب وEmployee 360.
- الحضور وPasskey/GPS كأساس برمجي.
- الطلبات وWorkflow.
- KPI الكامل بالمراحل المعتمدة.
- الأخبار والقرارات ومركز الإجراءات.
- الموقع والفيديو والتتبع.
- المهام والفريق والتقارير اليومية.
- الهيكل والمناصب وRole Builder.
- Recruitment Requisition وOnboarding.

## الأولوية التالية

1. تشغيل Supabase Runtime وإغلاق Persona RLS Tests.
2. إكمال Storage Buckets والسياسات والـMalware validation للمرفقات.
3. تطوير ATS Pipeline: المرشحون، المقابلات، Scorecards، العروض والتحويل إلى موظف.
4. العقود والمستندات والتوقيع والإقرارات.
5. الورديات والروستر والعمل الإضافي وتقويم العطلات.
6. Training/LMS والمهارات والشهادات والعهد.
7. الشكاوى ولجنة الخلافات ومحاضرها وقراراتها.
8. التقارير المجدولة وExecutive Briefs وPDF.
9. Push Notifications وDeep Links الفعلية.
10. CI Release Gates، Android AAB وStaging deployment.

## قاعدة الإكمال

لا تُعد أي وحدة مكتملة قبل وجود Database/RLS/API/UI/Audit/Tests/Acceptance Criteria، ولا يُسمح بصفحات أو أزرار غير موصولة ببيانات حقيقية.
