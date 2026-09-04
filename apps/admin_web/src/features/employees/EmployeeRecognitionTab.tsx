import { Award, CheckCircle2, Gift, Medal, Plus, ShieldCheck, Sparkles, Star, Trophy } from 'lucide-react';
import { useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useToast } from '../../ui/Toast';

interface RecognitionBadge {
  id: string;
  title: string;
  description: string;
  icon: typeof Award;
  earnedDate: string;
  level: 'gold' | 'silver' | 'bronze' | 'diamond';
  points: number;
}

const DEFAULT_BADGES: RecognitionBadge[] = [
  {
    id: 'b1',
    title: 'درع الالتزام والانضباط',
    description: 'تم تحقيقه لنسبة حضور كاملة 100% خلال آخر دورة عمل دون غياب.',
    icon: ShieldCheck,
    earnedDate: '2026-08-01',
    level: 'gold',
    points: 100,
  },
  {
    id: 'b2',
    title: 'وسام دقة المواعيد',
    description: 'سُجلت صفر دقائق تأخير عن مواعيد بدء الورديات خلال الشهر.',
    icon: Medal,
    earnedDate: '2026-07-15',
    level: 'silver',
    points: 50,
  },
  {
    id: 'b3',
    title: 'نجم الأداء المتميز (Top KPI)',
    description: 'تحقيق تقييم سنوي/دوري فاق التوقعات في محاور الأداء الأساسية.',
    icon: Star,
    earnedDate: '2026-06-30',
    level: 'diamond',
    points: 150,
  },
  {
    id: 'b4',
    title: 'المبادر الميداني الأول',
    description: 'سرعة استجابة عالية وتفانٍ في إتمام المأموريات والقوافل.',
    icon: Sparkles,
    earnedDate: '2026-05-20',
    level: 'gold',
    points: 80,
  },
];

const LEVEL_CLASSES: Record<RecognitionBadge['level'], { bg: string; border: string; text: string; badgeText: string }> = {
  diamond: {
    bg: 'bg-cyan-500/10 dark:bg-cyan-500/20',
    border: 'border-cyan-500/40',
    text: 'text-cyan-600 dark:text-cyan-400',
    badgeText: 'وسام ألماسي',
  },
  gold: {
    bg: 'bg-amber-500/10 dark:bg-amber-500/20',
    border: 'border-amber-500/40',
    text: 'text-amber-600 dark:text-amber-400',
    badgeText: 'وسام ذهبي',
  },
  silver: {
    bg: 'bg-slate-400/10 dark:bg-slate-400/20',
    border: 'border-slate-400/40',
    text: 'text-slate-600 dark:text-slate-300',
    badgeText: 'وسام فضي',
  },
  bronze: {
    bg: 'bg-orange-500/10 dark:bg-orange-500/20',
    border: 'border-orange-500/40',
    text: 'text-orange-600 dark:text-orange-400',
    badgeText: 'وسام برونزي',
  },
};

export function EmployeeRecognitionTab({ employeeId }: { employeeId: string }) {
  const auth = useAuth();
  const { toast } = useToast();
  const [badges, setBadges] = useState<RecognitionBadge[]>(DEFAULT_BADGES);
  const [showAddModal, setShowAddModal] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newDesc, setNewDesc] = useState('');
  const [newPoints, setNewPoints] = useState(50);
  const [newLevel, setNewLevel] = useState<RecognitionBadge['level']>('gold');

  const canGrantRecognition = Boolean(
    auth.access && (hasPermission(auth.access, 'people.employee.update_sensitive') || auth.access.workspaces?.includes('main_admin')),
  );

  const totalPoints = badges.reduce((sum, b) => sum + b.points, 0);

  const handleGrantBadge = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim()) return;

    const newBadge: RecognitionBadge = {
      id: `b-${Date.now()}`,
      title: newTitle.trim(),
      description: newDesc.trim() || 'تكريم خاص من الإدارة للتميز في الأداء والالتزام.',
      icon: Trophy,
      earnedDate: new Date().toISOString().split('T')[0],
      level: newLevel,
      points: newPoints,
    };

    setBadges([newBadge, ...badges]);
    setShowAddModal(false);
    setNewTitle('');
    setNewDesc('');
    toast({ message: `تم منح ${newBadge.title} للموظف بنجاح!`, tone: 'success' });
  };

  return (
    <div className="space-y-6">
      {/* بطاقة رصيد التميز والنقاط */}
      <section className="card p-6 border border-[var(--border)] bg-gradient-to-r from-[var(--surface)] via-[var(--surface-muted)] to-[var(--surface)]">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="flex size-14 items-center justify-center rounded-2xl bg-amber-500/15 text-amber-500 border border-amber-500/30 shadow-xs">
              <Trophy className="size-7" aria-hidden="true" />
            </div>
            <div>
              <h3 className="text-xl font-black">منظومة التقدير والتحفيز الوظيفي</h3>
              <p className="text-xs text-[var(--text-muted)] mt-1">
                سجل الأوسمة وشارات الاستحقاق الممنوحة تقديراً للإنجاز والانضباط الميداني
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2 text-center">
              <span className="text-xs font-bold text-[var(--text-muted)] block">رصيد نقاط التميز</span>
              <span className="text-2xl font-black text-amber-500 tabular">{totalPoints}</span>
            </div>
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-4 py-2 text-center">
              <span className="text-xs font-bold text-[var(--text-muted)] block">الأوسمة المحققة</span>
              <span className="text-2xl font-black text-[var(--brand-primary)] tabular">{badges.length}</span>
            </div>
            {canGrantRecognition && (
              <button
                type="button"
                onClick={() => setShowAddModal(true)}
                className="btn-primary flex items-center gap-2"
              >
                <Plus className="size-4" aria-hidden="true" />
                منح وسام تقدير
              </button>
            )}
          </div>
        </div>
      </section>

      {/* شبكة الأوسمة والشارات */}
      <section className="space-y-3">
        <h4 className="text-sm font-black text-[var(--text)]">الأوسمة والشارات المكتسبة ({badges.length})</h4>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {badges.map((badge) => {
            const Icon = badge.icon;
            const levelStyle = LEVEL_CLASSES[badge.level];
            return (
              <div
                key={badge.id}
                className={`card relative flex flex-col justify-between p-5 border ${levelStyle.border} ${levelStyle.bg} transition-all hover:shadow-md`}
              >
                <div>
                  <div className="flex items-start justify-between gap-2">
                    <span className={`flex size-11 items-center justify-center rounded-xl bg-[var(--surface)] shadow-xs ${levelStyle.text}`}>
                      <Icon className="size-6" aria-hidden="true" />
                    </span>
                    <span className="rounded-full bg-[var(--surface)] px-2 py-0.5 text-[11px] font-black shadow-xs">
                      +{badge.points} نقطة
                    </span>
                  </div>
                  <h5 className="mt-3 text-base font-black text-[var(--text)]">{badge.title}</h5>
                  <p className="mt-1 text-xs text-[var(--text-muted)] leading-relaxed">{badge.description}</p>
                </div>
                <div className="mt-4 flex items-center justify-between border-t border-[var(--border)] pt-3 text-[11px] text-[var(--text-muted)]">
                  <span className={`font-bold ${levelStyle.text}`}>{levelStyle.badgeText}</span>
                  <span className="tabular">{badge.earnedDate}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* نموذج منح وسام جديد */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-md p-6 border border-[var(--border)] shadow-xl animate-in fade-in">
            <h3 className="text-lg font-black mb-1">منح وسام تقدير للموظف</h3>
            <p className="text-xs text-[var(--text-muted)] mb-4">
              إضافة وسام استحقاق وتكريم لسجل الموظف مع مكافأة نقاط تميز
            </p>
            <form onSubmit={handleGrantBadge} className="space-y-4">
              <div>
                <label className="text-xs font-bold block mb-1">عنوان الوسام / التكريم</label>
                <input
                  type="text"
                  required
                  placeholder="مثال: نجم الشهر في خدمة العملاء"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  className="input w-full"
                />
              </div>

              <div>
                <label className="text-xs font-bold block mb-1">سبب التكريم والوصف</label>
                <textarea
                  rows={2}
                  placeholder="وصف الإنجاز أو الموقف المميز..."
                  value={newDesc}
                  onChange={(e) => setNewDesc(e.target.value)}
                  className="input w-full"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-bold block mb-1">مستوى الوسام</label>
                  <select
                    value={newLevel}
                    onChange={(e) => setNewLevel(e.target.value as RecognitionBadge['level'])}
                    className="input w-full"
                  >
                    <option value="diamond">ألماسي (Diamond)</option>
                    <option value="gold">ذهبي (Gold)</option>
                    <option value="silver">فضي (Silver)</option>
                    <option value="bronze">برونزي (Bronze)</option>
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold block mb-1">نقاط التميز الممنوحة</label>
                  <input
                    type="number"
                    min={10}
                    max={500}
                    step={10}
                    value={newPoints}
                    onChange={(e) => setNewPoints(Number(e.target.value))}
                    className="input w-full"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="btn-secondary"
                >
                  إلغاء
                </button>
                <button type="submit" className="btn-primary">
                  تأكيد ومنح الوسام
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
