import { ArrowRight, CheckCircle2, FileText, Scale } from 'lucide-react';
import { useNavigate } from 'react-router';

export function TermsPage() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-[var(--surface-muted)] py-12 px-4 sm:px-6 lg:px-8 text-right font-sans" dir="rtl">
      <div className="max-w-4xl mx-auto bg-[var(--surface)] p-8 sm:p-12 rounded-3xl shadow-xl border border-[var(--border)]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[var(--border)] pb-6 mb-8">
          <div>
            <div className="flex items-center gap-3">
              <div className="size-12 rounded-2xl bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] flex items-center justify-center">
                <Scale className="size-7" />
              </div>
              <div>
                <h1 className="text-2xl font-black text-[var(--text)]">شروط وأحكام الاستخدام</h1>
                <p className="text-sm text-[var(--text-muted)] mt-1">نظام إدارة وتشغيل الموارد البشرية — أحلى شباب (Ahla Shabab HR Platform)</p>
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={() => navigate(-1)}
            className="btn-secondary text-xs flex items-center gap-1.5 py-2 px-3"
          >
            <ArrowRight className="size-4" />
            رجوع
          </button>
        </div>

        <div className="text-xs text-[var(--text-muted)] mb-6 bg-[var(--surface-muted)] p-3 rounded-xl border border-[var(--border)] inline-block">
          تاريخ السريان: <strong>سبتمبر 2026</strong> | النسخة المؤسسية: <strong>1.0.0</strong>
        </div>

        <div className="space-y-8 text-sm text-[var(--text)] leading-relaxed">
          {/* 1. القبول بالاتفاقية */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              1. قبول الشروط والأحكام
            </h2>
            <p className="text-[var(--text-muted)]">
              يُعد استخدامك لمنصة الويب أو تطبيق الهاتف المحمول الخاص بنظام «أحلى شباب» إقراراً وموافقة صريحة على الالتزام بكافة الشروط والأحكام واللوائح التنظيمية الموضحة أدناه، بالإضافة إلى السياسات الداخلية للمؤسسة.
            </p>
          </section>

          {/* 2. الاستخدام المصرح به وحسابات الموظفين */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              2. الاستخدام المصرح به وسرية الحساب
            </h2>
            <p className="text-[var(--text-muted)]">
              الحساب الممنوح لكل موظف هو حساب شخصي ومخصص لأغراض العمل الرسمية فقط. يُحظر مشاركة بيانات الدخول أو كلمات المرور أو مفاتيح المرور (Passkeys) مع أي شخص آخر، ويتحمل صاحب الحساب المسؤولية القانونية والإدارية الكاملة عن أي إجراء أو توقيع أو تسجيل يتم من خلال حسابه.
            </p>
          </section>

          {/* 3. ضوابط تسجيل الحضور الميداني والنزاهة */}
          <section className="space-y-3">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              3. ضوابط تسجيل الحضور والانصراف والنزاهة
            </h2>
            <div className="p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-amber-900 dark:text-amber-200 text-xs space-y-2">
              <div className="flex items-center gap-2 font-bold text-sm">
                <FileText className="size-4" />
                قواعد مكافحة التلاعب الرقمي
              </div>
              <ul className="list-disc list-inside space-y-1">
                <li>يُحظر استخدام أي برمجيات لتزييف الموقع الجغرافي (Mock Location / Fake GPS). المنظومة تكشف وتلغي أي تسجيل مشبوه تلقائياً.</li>
                <li>يجب أن تكون صورة التحقق الحية (Selfie) للموظف نفسه داخل مقر العمل بدون أي حجب للوجه أو استخدام صور سابقة.</li>
                <li>تعتبر محاولة تسجيل الحضور نيابة عن زميل أو تقديم تقارير عمل وهمية مخالفة جسيمة تستوجب الإحالة إلى لجنة النزاعات الإدارية.</li>
              </ul>
            </div>
          </section>

          {/* 4. حجية التوقيع الإلكتروني والطلبات */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              4. حجية التوقيعات الرقمية والطلبات
            </h2>
            <p className="text-[var(--text-muted)]">
              تُعتبر التوقيعات الرقمية المنفذة عبر موديول التوقيع بالمنظومة أو الموافقات الصادرة عبر حسابات المدراء والإدارة ذات حجية قانونية وإدارية ملزمة ونافذة، ويتم توثيق كل حركة بالوقت والتاريخ وعنوان الـ IP وسجل التدقيق غير القابل للتعديل (Immutable Audit Trail).
            </p>
          </section>

          {/* 5. إنهاء الخدمة وإلغاء التفعيل */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              5. انتهاء الاستخدام وتعليق الحساب
            </h2>
            <p className="text-[var(--text-muted)]">
              تحتفظ المنشأة بالحق في إيقاف أو تعليق وصول أي حساب فور إنهاء علاقة العمل أو انتهاء العقد أو بناءً على قرار من لجنة الانضباط والحوكمة، مع تسوية كافة العهد والمستحقات عبر نموذج إخلاء الطرف المعتمد.
            </p>
          </section>

          {/* 6. التعديلات والتحديثات */}
          <div className="flex items-center gap-2 text-xs text-[var(--text-muted)] pt-4 border-t border-[var(--border)]">
            <CheckCircle2 className="size-4 text-emerald-500 shrink-0" />
            <span>تسري أي تحديثات على هذه الشروط فور نشرها على هذه الصفحة مع إشعار الموظفين في المنظومة.</span>
          </div>
        </div>
      </div>
    </div>
  );
}
