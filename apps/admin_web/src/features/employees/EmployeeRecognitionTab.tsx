import { Plus, Trophy } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useToast } from '../../ui/Toast';
import { getSupabase } from '../../core/supabase';

export interface HonorRecord {
  id: string;
  type: 'month' | 'week';
  rank: 1 | 2 | 3;
  category: 'attendance' | 'missions' | 'reports';
  title: string;
  achievement: string;
  periodLabel: string;
  earnedDate: string;
}

const RANK_BADGES = {
  1: {
    icon: '🥇',
    label: 'المركز الأول',
    bg: 'bg-amber-500/10 dark:bg-amber-500/20',
    border: 'border-amber-500/40',
    text: 'text-amber-600 dark:text-amber-400',
    badgeBg: 'bg-amber-500 text-white',
  },
  2: {
    icon: '🥈',
    label: 'المركز الثاني',
    bg: 'bg-slate-400/10 dark:bg-slate-400/20',
    border: 'border-slate-400/40',
    text: 'text-slate-600 dark:text-slate-300',
    badgeBg: 'bg-slate-400 text-white',
  },
  3: {
    icon: '🥉',
    label: 'المركز الثالث',
    bg: 'bg-orange-500/10 dark:bg-orange-500/20',
    border: 'border-orange-500/40',
    text: 'text-orange-600 dark:text-orange-400',
    badgeBg: 'bg-orange-500 text-white',
  },
};

const CATEGORY_LABELS = {
  attendance: 'الانضباط ودقة الحضور',
  missions: 'المأموريات الميدانية',
  reports: 'المهام والتقارير اليومية',
};

export function EmployeeRecognitionTab({ employeeId }: { employeeId: string }) {
  const auth = useAuth();
  const { toast } = useToast();
  const [records, setRecords] = useState<HonorRecord[]>([]);
  const [showAddModal, setShowAddModal] = useState(false);

  const [newType, setNewType] = useState<'month' | 'week'>('month');
  const [newRank, setNewRank] = useState<1 | 2 | 3>(1);
  const [newCategory, setNewCategory] = useState<'attendance' | 'missions' | 'reports'>('attendance');
  const [newPeriod, setNewPeriod] = useState('شهر سبتمبر 2026');
  const [newAchievement, setNewAchievement] = useState('');

  // استرجاع سجلات التكريم الحقيقية للموظف من قاعدة البيانات
  useEffect(() => {
    if (!employeeId) return;
    let isCancelled = false;
    getSupabase().then((sb) => {
      sb.from('recognitions')
        .select('*')
        .eq('recipient_employee_id', employeeId)
        .order('awarded_at', { ascending: false })
        .then(({ data }) => {
          if (isCancelled || !data) return;
          const mapped: HonorRecord[] = (data as Record<string, unknown>[]).map((r) => {
            const meta = (r.metadata as Record<string, unknown> | null) ?? null;
            return {
              id: String(r.id),
              type: (r.recognition_type === 'week' ? 'week' : 'month') as 'month' | 'week',
              rank: ((meta?.rank as number) ?? 1) as 1 | 2 | 3,
              category: ((meta?.category as string) ?? 'attendance') as 'attendance' | 'missions' | 'reports',
              title: String(r.title || 'تكريم في لوحة الشرف'),
              achievement: String(r.message || ''),
              periodLabel: String(meta?.periodLabel || 'الدورة الحالية'),
              earnedDate: r.awarded_at ? String(r.awarded_at).split('T')[0] : '',
            };
          });
          setRecords(mapped);
        });
    });
    return () => {
      isCancelled = true;
    };
  }, [employeeId]);

  const canGrant = Boolean(auth.access && (hasPermission(auth.access, 'people.employee.update_sensitive') || auth.access.workspaces?.includes('main_admin')));

  const monthCount = records.filter((r) => r.type === 'month' && r.rank === 1).length;
  const weekCount = records.filter((r) => r.type === 'week' && r.rank === 1).length;
  const totalPodiums = records.length;

  const handleAddHonor = async (e: React.FormEvent) => {
    e.preventDefault();

    const titlePrefix = newType === 'month' ? 'موظف الشهر' : 'موظف الأسبوع';
    const rankPrefix = newRank === 1 ? titlePrefix : `المركز ${newRank === 2 ? 'الثاني' : 'الثالث'}`;
    const generatedTitle = `${rankPrefix} — ${CATEGORY_LABELS[newCategory]}`;

    const newRecord: HonorRecord = {
      id: `honor-${Date.now()}`,
      type: newType,
      rank: newRank,
      category: newCategory,
      title: generatedTitle,
      achievement: newAchievement.trim() || 'تكريم رسمي للتميز الاستثنائي في الأداء والانضباط.',
      periodLabel: newPeriod.trim() || 'الدورة الحالية',
      earnedDate: new Date().toISOString().split('T')[0],
    };

    setRecords((prev) => [newRecord, ...prev]);
    setShowAddModal(false);
    setNewAchievement('');

    try {
      const sb = await getSupabase();
      await sb.from('recognitions').insert({
        recipient_employee_id: employeeId,
        recognition_type: newType,
        title: generatedTitle,
        message: newRecord.achievement,
        metadata: {
          rank: newRank,
          category: newCategory,
          periodLabel: newRecord.periodLabel,
        },
        awarded_at: new Date().toISOString(),
      });
      toast({ message: `تم إدراج الموظف في لوحة الشرف (${generatedTitle}) بنجاح!`, tone: 'success' });
    } catch {
      toast({ message: `تم تسجيل التكريم محلياً (${generatedTitle})`, tone: 'info' });
    }
  };

  return (
    <div className="space-y-6">
      {/* بطاقة ملخص لوحة الشرف */}
      <section className="card p-6 border border-[var(--border)] bg-gradient-to-r from-[var(--surface)] via-[var(--surface-muted)] to-[var(--surface)]">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex size-14 items-center justify-center rounded-2xl bg-amber-500/15 text-amber-500 border border-amber-500/30 shadow-xs">
              <Trophy className="size-7" aria-hidden="true" />
            </div>
            <div>
              <h3 className="text-xl font-black">لوحة الشرف وسجل التميز الوظيفي</h3>
              <p className="text-xs text-[var(--text-muted)] mt-1">سجل تكريمات موظف الأسبوع وموظف الشهر، والانضباط الميداني والأداء</p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2 text-center">
              <span className="text-xs font-bold text-[var(--text-muted)] block">موظف الشهر 🌟</span>
              <span className="text-2xl font-black text-amber-500 tabular">{monthCount}</span>
            </div>
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2 text-center">
              <span className="text-xs font-bold text-[var(--text-muted)] block">موظف الأسبوع ⚡</span>
              <span className="text-2xl font-black text-teal-600 dark:text-teal-400 tabular">{weekCount}</span>
            </div>
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2 text-center">
              <span className="text-xs font-bold text-[var(--text-muted)] block">منصة الشرف 🏆</span>
              <span className="text-2xl font-black text-[var(--brand-primary)] tabular">{totalPodiums}</span>
            </div>
            {canGrant && (
              <button type="button" onClick={() => setShowAddModal(true)} className="btn-primary flex items-center gap-2">
                <Plus className="size-4" aria-hidden="true" />
                إدراج في لوحة الشرف
              </button>
            )}
          </div>
        </div>
      </section>

      {/* قائمة التكريمات والشرف المحققة */}
      <section className="space-y-3">
        <h4 className="text-sm font-black text-[var(--text)]">سجل التكريمات في لوحة الشرف ({records.length})</h4>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {records.map((rec) => {
            const rankStyle = RANK_BADGES[rec.rank];
            return (
              <div
                key={rec.id}
                className={`card relative flex flex-col justify-between p-5 border ${rankStyle.border} ${rankStyle.bg} transition-all hover:shadow-md`}
              >
                <div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-2xl">{rankStyle.icon}</span>
                    <span className={`rounded-full px-2.5 py-0.5 text-[11px] font-black shadow-xs ${rankStyle.badgeBg}`}>
                      {rec.type === 'month' ? 'موظف الشهر 🌟' : 'موظف الأسبوع ⚡'}
                    </span>
                  </div>
                  <h5 className="mt-3 text-base font-black text-[var(--text)]">{rec.title}</h5>
                  <p className="mt-1 text-xs text-[var(--text-muted)] leading-relaxed">{rec.achievement}</p>
                </div>
                <div className="mt-4 flex items-center justify-between border-t border-[var(--border)] pt-3 text-[11px] text-[var(--text-muted)]">
                  <span className={`font-black ${rankStyle.text}`}>{rankStyle.label}</span>
                  <span className="font-semibold tabular">{rec.periodLabel}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* نافذة إدراج موظف في لوحة الشرف */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-6 border border-[var(--border)] shadow-xl animate-in fade-in">
            <div className="flex items-center gap-3 mb-2">
              <div className="size-9 rounded-xl bg-amber-500/15 text-amber-500 flex items-center justify-center">
                <Trophy className="size-5" />
              </div>
              <div>
                <h3 className="text-lg font-black">إدراج الموظف في لوحة الشرف</h3>
                <p className="text-xs text-[var(--text-muted)]">تكريم الموظف كـ موظف الأسبوع أو موظف الشهر وتوثيق إنجازه</p>
              </div>
            </div>

            <form onSubmit={handleAddHonor} className="space-y-4 mt-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold block mb-1">نوع التكريم</label>
                  <select value={newType} onChange={(e) => setNewType(e.target.value as 'month' | 'week')} className="input w-full">
                    <option value="month">موظف الشهر 🌟</option>
                    <option value="week">موظف الأسبوع ⚡</option>
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold block mb-1">المركز / الترتيب</label>
                  <select value={newRank} onChange={(e) => setNewRank(Number(e.target.value) as 1 | 2 | 3)} className="input w-full">
                    <option value={1}>المركز الأول 🥇</option>
                    <option value={2}>المركز الثاني 🥈</option>
                    <option value={3}>المركز الثالث 🥉</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="text-xs font-bold block mb-1">محور التميز</label>
                <select value={newCategory} onChange={(e) => setNewCategory(e.target.value as 'attendance' | 'missions' | 'reports')} className="input w-full">
                  <option value="attendance">الانضباط ودقة الحضور (Attendance)</option>
                  <option value="missions">المأموريات الميدانية (Field Missions)</option>
                  <option value="reports">المهام والتقارير اليومية (Daily Reports)</option>
                </select>
              </div>

              <div>
                <label className="text-xs font-bold block mb-1">فترة التكريم / الدورة</label>
                <input
                  type="text"
                  required
                  placeholder="مثال: شهر سبتمبر 2026 أو الأسبوع 39"
                  value={newPeriod}
                  onChange={(e) => setNewPeriod(e.target.value)}
                  className="input w-full"
                />
              </div>

              <div>
                <label className="text-xs font-bold block mb-1">الإنجاز المحقق والتفاصيل</label>
                <textarea
                  rows={3}
                  required
                  placeholder="مثال: حضور كامل بدون أي تأخير بنسبة 100% طوال الشهر، أو إنجاز 15 مأمورية ميدانية بدقة..."
                  value={newAchievement}
                  onChange={(e) => setNewAchievement(e.target.value)}
                  className="input w-full"
                />
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <button type="button" onClick={() => setShowAddModal(false)} className="btn-secondary">
                  إلغاء
                </button>
                <button type="submit" className="btn-primary">
                  تأكيد الإدراج في لوحة الشرف
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
