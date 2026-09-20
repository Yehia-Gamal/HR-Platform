import { useState, useEffect } from 'react';
import { Save, Settings, Plus, Trash2 } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { usePenaltySettings, useUpdatePenaltySettings, type PenaltySetting } from './usePenaltySettings';

interface Tier {
  min_late: number;
  max_late: number;
  amount: number;
  label: string;
}

function getValue<T>(settings: PenaltySetting[], key: string, fallback: T): T {
  const s = settings.find((x) => x.setting_key === key);
  return (s?.setting_value as T) ?? fallback;
}

export function PenaltySettingsPage() {
  const settings = usePenaltySettings();
  const updateSettings = useUpdatePenaltySettings();

  const [graceMinutes, setGraceMinutes] = useState(15);
  const [shiftStart, setShiftStart] = useState('10:00');
  const [doubledAmount, setDoubledAmount] = useState(500);
  const [maxDays, setMaxDays] = useState(2);
  const [autoCheckout, setAutoCheckout] = useState(true);
  const [autoCheckoutTime, setAutoCheckoutTime] = useState('18:00');
  const [weekends, setWeekends] = useState<string[]>(['Friday', 'Saturday']);
  const [tiers, setTiers] = useState<Tier[]>([]);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (settings.data && settings.data.length > 0) {
      setGraceMinutes(getValue(settings.data, 'grace_minutes', 15));
      setShiftStart(getValue(settings.data, 'shift_start', '10:00'));
      setDoubledAmount(getValue(settings.data, 'doubled_amount', 500));
      setMaxDays(getValue(settings.data, 'max_days_before_escalation', 2));
      setAutoCheckout(getValue(settings.data, 'auto_checkout_enabled', true));
      setAutoCheckoutTime(getValue(settings.data, 'auto_checkout_time', '18:00'));
      setWeekends(getValue(settings.data, 'weekends', ['Friday', 'Saturday']));
      setTiers(getValue(settings.data, 'tiers', []));
    }
  }, [settings.data]);

  if (settings.isError) return <ErrorState description={safeErrorMessage(settings.error)} />;
  if (settings.isLoading) return <ListSkeleton rows={6} label="جارٍ تحميل الإعدادات…" />;
  if (!settings.data || settings.data.length === 0) return <EmptyState title="لا توجد إعدادات" description="لم يتم العثور على أي إعدادات للغرامات." />;

  const handleSave = async () => {
    try {
      await updateSettings.mutateAsync([
        { key: 'grace_minutes', value: graceMinutes },
        { key: 'shift_start', value: shiftStart },
        { key: 'doubled_amount', value: doubledAmount },
        { key: 'max_days_before_escalation', value: maxDays },
        { key: 'auto_checkout_enabled', value: autoCheckout },
        { key: 'auto_checkout_time', value: autoCheckoutTime },
        { key: 'weekends', value: weekends },
        { key: 'tiers', value: tiers },
      ]);
      setDirty(false);
    } catch {
      // Error handled by mutation
    }
  };

  const addTier = () => {
    setTiers([...tiers, { min_late: 0, max_late: 0, amount: 0, label: '' }]);
    setDirty(true);
  };

  const removeTier = (index: number) => {
    setTiers(tiers.filter((_, i) => i !== index));
    setDirty(true);
  };

  const updateTier = (index: number, field: keyof Tier, value: string | number) => {
    const updated = [...tiers];
    updated[index] = { ...updated[index], [field]: value };
    setTiers(updated);
    setDirty(true);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="إعدادات الغرامات الفورية"
        description="تعديل فترات السماح، الشرائح، وال Rules الخاصة بالحضور والانصراف."
        actions={
          <button
            type="button"
            onClick={() => void handleSave()}
            disabled={!dirty || updateSettings.isPending}
            className="btn-primary flex items-center gap-1.5"
          >
            <Save className="size-4" />
            {updateSettings.isPending ? 'جارٍ الحفظ…' : 'حفظ الإعدادات'}
          </button>
        }
      />

      {/* ─── الإعدادات الأساسية ──────────────────────────────────────── */}
      <section className="card p-6 space-y-5">
        <div className="flex items-center gap-2">
          <Settings className="size-4 text-[var(--brand-primary)]" />
          <h2 className="text-sm font-black text-[var(--text-primary)]">الإعدادات الأساسية</h2>
        </div>

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Field
            label="موعد بداية الدوام"
            value={shiftStart}
            onChange={(v) => { setShiftStart(v); setDirty(true); }}
            type="time"
          />
          <Field
            label="فترة السماح (دقائق)"
            value={graceMinutes}
            onChange={(v) => { setGraceMinutes(Number(v)); setDirty(true); }}
            type="number"
            min={0}
            max={60}
          />
          <Field
            label="مضاعفة الغرامة (ج.م)"
            value={doubledAmount}
            onChange={(v) => { setDoubledAmount(Number(v)); setDirty(true); }}
            type="number"
            min={0}
          />
          <Field
            label="أيام قبل التصعيد"
            value={maxDays}
            onChange={(v) => { setMaxDays(Number(v)); setDirty(true); }}
            type="number"
            min={1}
            max={7}
          />
          <div className="flex items-center gap-3">
            <label className="text-xs font-bold text-[var(--text-primary)]">إغلاق تلقائي</label>
            <button
              type="button"
              onClick={() => { setAutoCheckout(!autoCheckout); setDirty(true); }}
              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                autoCheckout ? 'bg-[var(--brand-primary)]' : 'bg-gray-300 dark:bg-gray-600'
              }`}
            >
              <span className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                autoCheckout ? 'translate-x-6' : 'translate-x-1'
              }`} />
            </button>
          </div>
          {autoCheckout && (
            <Field
              label="وقت الإغلاق التلقائي"
              value={autoCheckoutTime}
              onChange={(v) => { setAutoCheckoutTime(v); setDirty(true); }}
              type="time"
            />
          )}
        </div>

        {/* عطلة نهاية الأسبوع */}
        <div>
          <label className="block text-xs font-bold text-[var(--text-primary)] mb-2">أيام العطلة الأسبوعية</label>
          <div className="flex gap-2">
            {['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'].map((day) => {
              const dayAr: Record<string, string> = { Saturday: 'السبت', Sunday: 'الأحد', Monday: 'الاثنين', Tuesday: 'الثلاثاء', Wednesday: 'الأربعاء', Thursday: 'الخميس', Friday: 'الجمعة' };
              const isSelected = weekends.includes(day);
              return (
                <button
                  key={day}
                  type="button"
                  onClick={() => {
                    setWeekends(isSelected ? weekends.filter((d) => d !== day) : [...weekends, day]);
                    setDirty(true);
                  }}
                  className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-all ${
                    isSelected
                      ? 'bg-[var(--brand-primary)] text-white'
                      : 'border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--brand-primary)]'
                  }`}
                >
                  {dayAr[day]}
                </button>
              );
            })}
          </div>
        </div>
      </section>

      {/* ─── شرائح الغرامات ──────────────────────────────────────────── */}
      <section className="card p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-black text-[var(--text-primary)]">شرائح الغرامات</h2>
          <button
            type="button"
            onClick={addTier}
            className="flex items-center gap-1 text-xs font-bold text-[var(--brand-primary)] hover:underline"
          >
            <Plus className="size-3.5" />
            إضافة شريحة
          </button>
        </div>

        {tiers.length === 0 ? (
          <p className="text-xs text-[var(--text-muted)]">لا توجد شرائح معرفة.</p>
        ) : (
          <div className="space-y-2">
            {tiers.map((tier, i) => (
              <div key={i} className="flex items-center gap-3 rounded-xl border border-[var(--border)] p-3">
                <input
                  type="text"
                  value={tier.label}
                  onChange={(e) => updateTier(i, 'label', e.target.value)}
                  placeholder="الاسم"
                  className="input-field flex-1 text-xs"
                />
                <input
                  type="number"
                  value={tier.min_late}
                  onChange={(e) => updateTier(i, 'min_late', Number(e.target.value))}
                  placeholder="من"
                  className="input-field w-20 text-xs text-center"
                  min={0}
                />
                <span className="text-xs text-[var(--text-muted)]">—</span>
                <input
                  type="number"
                  value={tier.max_late}
                  onChange={(e) => updateTier(i, 'max_late', Number(e.target.value))}
                  placeholder="إلى"
                  className="input-field w-20 text-xs text-center"
                  min={0}
                />
                <span className="text-xs text-[var(--text-muted)]">دقيقة</span>
                <input
                  type="number"
                  value={tier.amount}
                  onChange={(e) => updateTier(i, 'amount', Number(e.target.value))}
                  placeholder="المبلغ"
                  className="input-field w-24 text-xs text-center"
                  min={0}
                />
                <span className="text-xs text-[var(--text-muted)]">ج.م</span>
                <button
                  type="button"
                  onClick={() => removeTier(i)}
                  className="p-1.5 text-red-400 hover:text-red-600 transition-colors"
                >
                  <Trash2 className="size-4" />
                </button>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function Field({ label, value, onChange, type = 'text', min, max }: {
  label: string;
  value: string | number;
  onChange: (v: string) => void;
  type?: string;
  min?: number;
  max?: number;
}) {
  return (
    <div>
      <label className="block text-xs font-bold text-[var(--text-primary)] mb-1">{label}</label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        min={min}
        max={max}
        className="input-field w-full text-sm"
      />
    </div>
  );
}
