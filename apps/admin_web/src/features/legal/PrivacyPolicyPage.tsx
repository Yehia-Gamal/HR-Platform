import { ArrowRight, Lock, MapPin, Camera, Bell, ShieldCheck } from 'lucide-react';
import { useNavigate } from 'react-router';

export function PrivacyPolicyPage() {
  const navigate = useNavigate();

  return (
    <div className="min-h-screen bg-[var(--surface-muted)] py-12 px-4 sm:px-6 lg:px-8 text-right font-sans" dir="rtl">
      <div className="max-w-4xl mx-auto bg-[var(--surface)] p-8 sm:p-12 rounded-3xl shadow-xl border border-[var(--border)]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[var(--border)] pb-6 mb-8">
          <div>
            <div className="flex items-center gap-3">
              <div className="size-12 rounded-2xl bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] flex items-center justify-center">
                <ShieldCheck className="size-7" />
              </div>
              <div>
                <h1 className="text-2xl font-black text-[var(--text)]">سياسة الخصوصية وحماية البيانات</h1>
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
          تاريخ آخر تحديث: <strong>سبتمبر 2026</strong> | رقم الإصدار: <strong>1.0.0</strong>
        </div>

        <div className="space-y-8 text-sm text-[var(--text)] leading-relaxed">
          {/* 1. مقدمة */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              1. مقدمة والتزامنا بالخصوصية
            </h2>
            <p className="text-[var(--text-muted)]">
              تلتزم منظومة «أحلى شباب» بحماية خصوصية وأمان بيانات الموظفين والمستخدمين بأعلى المعايير المهنية والقانونية. تهدف هذه السياسة إلى توضيح كيفية جمع واستخدام وتخزين وحماية بياناتكم عند استخدام منصة الويب وتطبيق الهاتف الذكي المخصص للموظفين.
            </p>
          </section>

          {/* 2. البيانات التي نقوم بجمعها */}
          <section className="space-y-3">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              2. البيانات وصلاحيات الوصول المطلوبة
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
              <div className="p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/50 space-y-2">
                <div className="flex items-center gap-2 font-bold text-[var(--brand-primary)]">
                  <MapPin className="size-5 text-rose-500" />
                  بيانات الموقع الجغرافي (Location)
                </div>
                <p className="text-xs text-[var(--text-muted)]">
                  تُطلب إحداثيات الموقع (GPS) حصراً عند قيام الموظف بتسجيل الحضور والانصراف (Punch) للتحقق من التواجد الفعلي داخل النطاق الجغرافي المعتمد للفرع أو موقع العمل الميداني. لا يتم تتبع الموقع بشكل مستمر في الخلفية إلا عند تفعيل جلسة تتبع المهام الميدانية الرسمية المصرح بها من الإدارة.
                </p>
              </div>

              <div className="p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/50 space-y-2">
                <div className="flex items-center gap-2 font-bold text-[var(--brand-primary)]">
                  <Camera className="size-5 text-amber-500" />
                  الكاميرا والتحقق بالصورة (Camera & Selfie)
                </div>
                <p className="text-xs text-[var(--text-muted)]">
                  تُستخدم الكاميرا حصراً لالتقاط صورة التحقق الحية (Selfie Verification) أثناء إثبات الحضور ومطابقة الهوية لمنع تسجيل الحضور بالنيابة، أو لرفع صور المستندات والتقارير والعهد.
                </p>
              </div>

              <div className="p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/50 space-y-2">
                <div className="flex items-center gap-2 font-bold text-[var(--brand-primary)]">
                  <Bell className="size-5 text-blue-500" />
                  الإشعارات الفورية (Push Notifications)
                </div>
                <p className="text-xs text-[var(--text-muted)]">
                  تُستخدم إشعارات FCM وإشعارات الويب لإرسال التنبيهات التشغيلية الحيوية مثل: قرارات قبول أو رفض الإجازات، إشعارات الورديات، وقسائم الرواتب، والتعاميم الإدارية العاجلة.
                </p>
              </div>

              <div className="p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/50 space-y-2">
                <div className="flex items-center gap-2 font-bold text-[var(--brand-primary)]">
                  <Lock className="size-5 text-emerald-500" />
                  بيانات القياس الحيوي وجهاز الهاتف (Biometrics)
                </div>
                <p className="text-xs text-[var(--text-muted)]">
                  يدعم التطبيق المصادقة بالبصمة الحيوية (TouchID/FaceID) أو Passkeys المخزنة محلياً في شريحة الهاتف الآمنة (Secure Enclave). لا تُرسل بيانات بصمة الإصبع أو الوجه إلى خوادمنا إطلاقاً.
                </p>
              </div>
            </div>
          </section>

          {/* 3. أمن وتشفير البيانات */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              3. أمن وتشفير البيانات (Data Security)
            </h2>
            <p className="text-[var(--text-muted)]">
              تُخزن جميع البيانات داخل خوادم مؤمنة بتشفير AES-256 أثناء التخزين، وتشفير TLS 1.3 أثناء النقل. تخضع قواعد البيانات لسياسات أمان صارمة على مستوى الصف (Row-Level Security) بحيث لا يمكن لأي مستخدم الوصول إلى بيانات غير مصرح له بها.
            </p>
          </section>

          {/* 4. عدم مشاركة البيانات مع جهات خارجية */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              4. عدم مشاركة البيانات أو بيعها
            </h2>
            <p className="text-[var(--text-muted)]">
              نحن لا نبيع أو نؤجر أو نشارك أي بيانات شخصية للموظفين مع أي أطراف إعلانية أو تجارية خارجية. البيانات مخصصة حصرياً لإدارة العمليات الداخلية وتنظيم شؤون الموظفين وفقاً للوائح العمل.
            </p>
          </section>

          {/* 5. حذف الحساب والبيانات */}
          <section className="space-y-2">
            <h2 className="text-lg font-bold text-[var(--text)] flex items-center gap-2">
              <span className="size-2 rounded-full bg-[var(--brand-primary)]" />
              5. حقوق الموظف وحذف الحساب (Account Deletion)
            </h2>
            <p className="text-[var(--text-muted)]">
              يحق للموظف طلب تصحيح بياناته أو تقديم طلب حذف الحساب الشخصي من خلال التواصل مع مسؤول الموارد البشرية بالمنشأة، أو عبر خيار تقديم التماس في بوابة النزاعات والخدمة الذاتية بالتطبيق.
            </p>
          </section>

          {/* 6. التواصل */}
          <section className="p-4 rounded-2xl bg-[var(--brand-primary)]/5 border border-[var(--brand-primary)]/20 text-xs text-[var(--text-muted)]">
            لأي استفسارات قانونية أو تقنية تتعلق بسياسة الخصوصية وحماية البيانات، يرجى التواصل مع فريق الأمان والدعم عبر البريد الإلكتروني الرسمي للمؤسسة.
          </section>
        </div>
      </div>
    </div>
  );
}
