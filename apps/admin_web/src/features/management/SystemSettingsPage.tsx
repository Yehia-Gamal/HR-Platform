import { useMemo, useState } from 'react';
import { Clock3, Save, Settings as SettingsIcon } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { PageHeader } from '../../ui/PageHeader';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { useEditableSystemSettings, useUpdateSystemSettings, type SystemSetting } from '../finance/useFinancialExtensions';

function displayValue(setting: SystemSetting): string {
  const v = setting.value;
  if (v === null || v === undefined) return '';
  return String(v).replace(/^"(.*)"$/, '$1');
}

export function SystemSettingsPage() {
  const settings = useEditableSystemSettings();
  const update = useUpdateSystemSettings();
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [saveMsg, setSaveMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const groups = useMemo(() => {
    const map = new Map<string, SystemSetting[]>();
    for (const s of settings.data ?? []) {
      const g = s.groupName ?? 'عام';
      const arr = map.get(g) ?? [];
      arr.push(s);
      map.set(g, arr);
    }
    return Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0], 'ar'));
  }, [settings.data]);

  const groupLabel = (key: string): string => {
    const labels: Record<string, string> = {
      general: 'عام',
      requests: 'الطلبات',
      attendance: 'الحضور والانصراف',
      payroll: 'الرواتب',
      cron: 'المهام المجدولة',
      live_location: 'تحديد الموقع',
    };
    return labels[key] ?? key;
  };

  const handleSave = async (key: string) => {
    const raw = drafts[key];
    if (raw === undefined) return;
    const current = settings.data?.find((s) => s.key === key);
    if (!current) return;
    let value: string | boolean | number | unknown = raw;
    if (current.valueType === 'boolean') value = raw === 'true';
    else if (current.valueType === 'number' || current.valueType === 'integer') value = Number(raw);
    else if (current.valueType === 'json') {
      try {
        value = JSON.parse(raw);
      } catch {
        setSaveMsg({ ok: false, text: 'قيمة JSON غير صالحة.' });
        return;
      }
    }
    await update.mutateAsync({ [key]: value });
    setSaveMsg({ ok: true, text: `تم حفظ "${current.labelAr ?? key}" بنجاح.` });
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="النظام"
        title="إعدادات النظام"
        description="تعديل القيم التشغيلية للنظام: مهلات الطلبات، إعدادات الحضور، الرواتب، والمهام المجدولة."
        actions={
          <button
            type="button"
            className="btn-primary"
            disabled={update.isPending || Object.keys(drafts).length === 0}
            onClick={() => {
              const keys = Object.keys(drafts);
              if (keys.length === 0) return;
              void Promise.all(keys.map((k) => handleSave(k))).then(() => setDrafts({}));
            }}
          >
            <Save className="size-4" aria-hidden="true" />
            {update.isPending ? 'جارٍ الحفظ…' : 'حفظ الكل'}
          </button>
        }
      />

      {saveMsg && (
        <div className={`rounded-xl p-3 text-sm ${saveMsg.ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-600'}`} role="status">
          {saveMsg.text}
        </div>
      )}

      {settings.isError ? (
        <ErrorState description={safeErrorMessage(settings.error)} onRetry={() => void settings.refetch()} />
      ) : settings.isLoading ? (
        <ListSkeleton rows={5} label="جارٍ تحميل الإعدادات…" />
      ) : groups.length === 0 ? (
        <div className="card p-8 text-center">
          <SettingsIcon className="mx-auto size-10 text-[var(--text-muted)]" aria-hidden="true" />
          <p className="mt-3 font-bold">لا توجد إعدادات قابلة للتعديل.</p>
        </div>
      ) : (
        <div className="grid gap-5 xl:grid-cols-2">
          {groups.map(([group, items]) => (
            <article key={group} className="card p-5">
              <h2 className="flex items-center gap-2 font-black">
                <Clock3 className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                {groupLabel(group)}
              </h2>
              <div className="mt-4 space-y-4">
                {items.map((s) => {
                  const val = displayValue(s);
                  const isDirty = drafts[s.key] !== undefined && drafts[s.key] !== val;
                  return (
                    <div key={s.key} className={`rounded-xl p-4 transition ${isDirty ? 'bg-amber-50 ring-1 ring-amber-300' : 'bg-[var(--surface-muted)]'}`}>
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-black">{s.labelAr ?? s.key}</p>
                          {s.description ? <p className="muted mt-1 text-xs leading-5">{s.description}</p> : null}
                          <p className="muted mt-1 font-mono text-[11px]">
                            {s.key} · {s.valueType}
                          </p>
                        </div>
                        {isDirty && <span className="rounded-full bg-amber-200 px-2 py-0.5 text-[10px] font-black text-amber-800">غير محفوظ</span>}
                      </div>
                      {s.valueType === 'boolean' ? (
                        <select className="input mt-3" value={drafts[s.key] ?? val} onChange={(ev) => setDrafts((d) => ({ ...d, [s.key]: ev.target.value }))}>
                          <option value="true">نعم</option>
                          <option value="false">لا</option>
                        </select>
                      ) : (
                        <textarea
                          className="input mt-3 min-h-[64px] font-mono text-xs"
                          dir="ltr"
                          value={drafts[s.key] ?? val}
                          onChange={(ev) => setDrafts((d) => ({ ...d, [s.key]: ev.target.value }))}
                        />
                      )}
                      <div className="mt-2 flex justify-end">
                        <button type="button" className="btn-ghost text-xs" disabled={update.isPending} onClick={() => void handleSave(s.key)}>
                          حفظ
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}
