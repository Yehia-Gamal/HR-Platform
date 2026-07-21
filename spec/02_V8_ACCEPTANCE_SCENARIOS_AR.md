# اختبارات القبول V8 — Governance, Automation & Process Intelligence

> تضاف هذه السيناريوهات إلى اختبارات V7 ولا تستبدلها. لا تُفعّل الوحدة قبل نجاح سيناريوهاتها واختبارات RLS الخاصة بها.

## A. مركز الإجراءات الموحد

1. يرى المستخدم فقط عناصر الإجراءات التي يملك دورًا ونطاقًا فعّالين لتنفيذها.
2. API مباشر لعنصر خارج النطاق يُرفض ولا يكشف عنوان العنصر.
3. ترتيب الأولويات يعتمد على قواعد خادمية موثقة.
4. Batch Approval لا يظهر للعمليات الحساسة المحظورة.
5. إعادة إرسال نفس Action Token لا ينفذ العملية مرتين.
6. كل إجراء يسجل Before/After وActor وReason وCorrelation ID.
7. Deep Link يتحقق من الجلسة والصلاحية قبل عرض البيانات.
8. Push حساس لا يعرض النص الكامل على شاشة القفل.

## B. Executive Enterprise Inbox

9. المدير التنفيذي يرى Critical/Today/Review/Information منفصلة.
10. يستطيع إضافة Annotation دون تغيير التقرير الأصلي.
11. Voice Note تتحول إلى Draft ولا تنشر تلقائيًا.
12. العمليات الحساسة تطلب Step-up Authentication.
13. يستطيع إعادة العنصر للسكرتير مع سبب ومطلوب واضح.
14. Delegation محدد المدة والنطاق وينتهي تلقائيًا.
15. Briefing Offline للقراءة والملاحظات فقط، ولا يسمح باعتماد حساس Offline.

## C. المناصب وHeadcount وCapacity

16. يمكن وجود Position شاغر دون Employee.
17. تعيين موظف لمنصب يحدث بسجل effective-dated.
18. لا يسمح بإشغال منصب واحد من شخصين إلا إذا سمحت السياسة بنسبة FTE.
19. Acting Assignment يمنح صلاحيات مؤقتة فقط وينتهي تلقائيًا.
20. Headcount Plan لا يغير الموظفين الفعليين قبل الاعتماد والتنفيذ.
21. Capacity تحسب الوردية والإجازة والمهمة دون تكرار الساعات.
22. المستخدم لا يرى تكاليف الرواتب ضمن Capacity دون صلاحية مالية.

## D. Process Mining

23. كل Workflow يكتب Event Log بترتيب زمني خادمي.
24. لا يمكن للمستخدم تعديل أو حذف Event Log.
25. Process Variant يعرض المسار الفعلي من الأحداث الأصلية.
26. Conformance يحدد الانحراف عن نسخة SOP الصحيحة وقت الحدث.
27. بيانات التحليل تحترم masking والصلاحيات.
28. لا ينتج Process Mining جزاءً أو اتهامًا تلقائيًا.

## E. Digital Twin & Scenario Lab

29. السيناريو لا يعدل Production Data.
30. يمكن مقارنة Baseline وسيناريوهين على الأقل.
31. Impact يوضح الافتراضات ومصدر الأرقام ووقت التحديث.
32. تطبيق السيناريو يحتاج Change Plan واعتمادات منفصلة.
33. فشل خطوة في Change Plan لا يترك هيكلًا جزئيًا دون حالة استكمال/تعويض.

## F. Automation Studio

34. كل Rule لها Version وحالات Draft/Test/Approved/Active.
35. لا يستطيع منشئ Automation حساسة اعتمادها منفردًا.
36. Dry Run لا يرسل Notifications أو يغير بيانات Production.
37. Event مكرر لا يكرر Action بسبب Idempotency.
38. Loop Detection يمنع أتمتة تستدعي نفسها بلا نهاية.
39. Dead-letter يحتفظ بالفشل دون فقد الحدث.
40. Kill Switch يوقف القاعدة ولا يحذف سجل التشغيل.
41. Automation لا تتجاوز صلاحية المستخدم أو Service Policy.

## G. Service Catalog & Cases

42. كل خدمة تعرض SLA والمتطلبات والمالك.
43. المستخدم غير المؤهل لا يستطيع تقديم الخدمة عبر API.
44. Case يحفظ الأطراف والأدلة والمهام في Timeline واحد.
45. عضو قضية يرى فقط الحقول المسموحة له.
46. تعارض المصالح يمنع عضو اللجنة من المشاركة وفق السياسة.
47. Legal Hold يمنع حذف الأدلة المرتبطة.

## H. Evidence Vault والتوقيع

48. Hash المستند يتحقق عند الرفع وعند العرض الحساس.
49. لا يمكن استبدال Original Evidence؛ ينشأ Version جديد.
50. كل مشاهدة وتنزيل حساس يسجلان.
51. Signed URL قصير ولا يعمل بعد انتهائه.
52. التوقيع مرتبط بنسخة مستند محددة وHash محدد.
53. تعديل المستند بعد توقيع طرف يبطل مسار التوقيع ويطلب إصدارًا جديدًا.
54. Retention يحذف الملف بعد المدة إلا عند Legal Hold.

## I. SOP والجودة والتدقيق

55. SOP Instance يستخدم النسخة الفعالة وقت البدء.
56. لا يمكن تجاوز خطوة إلزامية دون Exception معتمد.
57. Finding عالية الخطورة تحتاج CAPA وOwner وDue Date.
58. إغلاق CAPA يتطلب Evidence وEffectiveness Review.
59. Auditor لا يعدل السجل التشغيلي الذي يدققه.
60. Compliance Calendar يمنع الإشعار المكرر لنفس الالتزام والفترة.

## J. الاجتماعات والقرارات

61. Meeting Mode يعرض Agenda والملفات حسب الصلاحية.
62. قرار الاجتماع ينشئ Action Items بمسؤولين ومواعيد.
63. التصويت السري لا يكشف اختيار الفرد.
64. Decision Impact Review يقارن Baseline بالنتيجة الفعلية.
65. تعديل القرار المنشور يتم عبر Amendment لا تعديل صامت.

## K. Notification Intelligence

66. الأحداث المتكررة تُجمع وفق قواعد معلنة.
67. Critical alert لا يدخل Weekly Digest.
68. Quiet Hours لا تكتم تنبيهًا أمنيًا إلزاميًا.
69. Delivery fallback لا يرسل بيانات حساسة عبر قناة غير مصرح بها.
70. Attention Budget لا يؤخر Action لها Deadline قانوني.

## L. Data Governance

71. كل عنصر حساس في Data Catalog له Owner وتصنيف وRetention.
72. Data Contract breaking change يفشل Contract Tests.
73. المستخدم غير المصرح لا يرى Data Lineage لجدول حساس.
74. Quality Auto-fix يعرض Preview ويسجل Before/After.
75. Waiver له مالك وسبب وتاريخ انتهاء.
76. Knowledge Graph لا يكشف علاقة أو Node خارج RLS.

## M. AI Governance

77. كل AI Use Case مسجل قبل الإنتاج.
78. RAG لا يسترجع مستندًا غير مصرح للمستخدم.
79. الإجابة تعرض مصادرها أو توضح عدم وجود مصدر كافٍ.
80. Prompt Injection داخل مستند لا يغير تعليمات النظام.
81. البيانات عالية الحساسية تُحجب أو لا ترسل لمزود خارجي حسب السياسة.
82. Human Decision Ledger يسجل قبول/رفض الاقتراح وسببه.
83. AI Kill Switch يعطل الاستخدام دون تعطيل العمليات الأساسية.
84. لا يصدر AI قرار فصل أو جزاء أو ترقية أو راتب نهائيًا.

## N. التدريب وتبني المنتج

85. Sandbox لا يقرأ أو يكتب Production.
86. Guided Tour تختلف حسب Workspace.
87. Adoption Analytics لا تسجل محتوى الحقول الحساسة.
88. Feedback Screenshot يتطلب موافقة ويطبق Redaction.

## O. Release & Resilience

89. Release Gate يفشل عند وجود P0/P1.
90. Migration Dry Run يعمل على نسخة Staging مماثلة.
91. Restore Test موثق وحديث قبل Release حساس.
92. Contract Tests تفشل عند تغير غير متوافق.
93. Event مكرر أثناء Chaos Test لا ينشئ بيانات مكررة.
94. فشل Push لا يفشل العملية الأساسية.
95. فشل Storage أثناء Evidence Upload لا ينشئ سجلًا معتمدًا بلا ملف.
96. التطبيق يتعافى من Token Expiry دون فقد Draft غير حساس.

## P. المعمارية الموحدة

97. يوجد Flutter App وظيفي واحد لجميع Workspaces.
98. يوجد React App واحدة لـHR/Main Admin/Product Operations.
99. Workspace Switching لا يغير Backend Permissions.
100. لا يُنشأ Chat داخلي كامل في Release 1.

## Release Gate V8

لا يبدأ Phase 4 قبل نجاح V7 Foundation Gate. ولا يبدأ Process Mining أو Digital Twin قبل اكتمال Event Catalog وOutbox وData Quality الأساسية.
