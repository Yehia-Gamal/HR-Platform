import { Clock, Crosshair, MapPin, ShieldAlert } from 'lucide-react';
import { useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { LiveLocationMap, type MapPoint } from './LiveLocationMap';
import type { LiveLocationResponseData, LocationPoint } from './controlCenterTypes';
import { useLiveLocationMapUrl, useLiveLocationResponse } from './useControlCenters';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';

// بطاقة نتيجة طلب الموقع الكاملة (القسم 10): خريطة + عنوان تقريبي + دقة + توقيتات.
// V17 §9: video permanently disabled — video player, legal hold, and URL signing UI removed.

function fmt(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  return d.toLocaleString('ar-EG', { hour: '2-digit', minute: '2-digit', second: '2-digit', day: '2-digit', month: '2-digit' });
}

function num(v: unknown): number | null {
  return typeof v === 'number' ? v : null;
}

export function LiveLocationResultCard({ requestId }: { requestId: string }) {
  const { toast } = useToast();
  const [mapSnapshotUrl, setMapSnapshotUrl] = useState<string | null>(null);
  const mapUrlCmd = useLiveLocationMapUrl();

  const req = typeof requestId === 'string' ? requestId : null;
  const response = useLiveLocationResponse(req, true);
  const data = response.data as LiveLocationResponseData | null | undefined;

  if (response.isLoading) {
    return <SkeletonCard className="h-72" />;
  }
  if (response.isError || !data) {
    return <ErrorState title="تعذّر تحميل النتيجة" description={safeErrorMessage(response.error)} onRetry={() => void response.refetch()} />;
  }

  const request = data.request ?? { status: 'pending', reason: null, requestedAt: null, respondedAt: null };
  const employee = data.employee ?? { name: null, employeeCode: null, jobTitle: null, department: null };
  const points: LocationPoint[] = Array.isArray(data.points) ? data.points : [];
  // V17 §9: video data ignored — video permanently disabled.
  const latest = points.length ? points[points.length - 1] : null;
  const latestAccuracy = latest ? num(latest.accuracy) : null;

  const mapPoints: MapPoint[] = points
    .filter((p) => num(p.latitude) !== null && num(p.longitude) !== null)
    .map((p, i) => ({
      id: p.id ?? String(i),
      lat: p.latitude,
      lng: p.longitude,
      accuracy: num(p.accuracy),
      label: employee.name ?? 'الموظف',
      sublabel: p.addressAr ?? null,
    }));

  async function loadMapSnapshot() {
    try {
      setMapSnapshotUrl(await mapUrlCmd.mutateAsync(requestId));
    } catch {
      toast({ message: 'تعذر تحميل لقطة الخريطة', tone: 'error' });
    }
  }

  return (
    <div className="space-y-5">
      <article className="card p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <UserAvatar displayName={employee.name ?? 'الموظف'} />
            <div>
              <h2 className="text-lg font-black">{employee.name ?? 'الموظف'}</h2>
              <p className="muted mt-1 text-xs">
                {employee.employeeCode ?? '—'} · {employee.jobTitle ?? 'دون مسمى'} · {employee.department ?? 'دون إدارة'}
              </p>
            </div>
            <p className="muted mt-1 text-xs">
              طلب من: {data.requesterName ?? '—'} · السبب: {request.reason ?? '—'}
            </p>
          </div>
          <StatusBadge value={request.status ?? 'pending'} />
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
          <Stat icon={Clock} label="أُرسل" value={fmt(request.requestedAt)} />
          <Stat icon={Clock} label="استجاب" value={fmt(request.respondedAt)} />
          <Stat icon={Crosshair} label="دقة GPS" value={latestAccuracy !== null ? `${Math.round(latestAccuracy)} متر` : '—'} />
          <Stat icon={ShieldAlert} label="Mock GPS" value={latest?.isMock ? 'مشتبه' : 'لا'} />
        </div>
      </article>

      {mapPoints.length ? (
        <article className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-4">
            <h3 className="font-black">الموقع على الخريطة</h3>
          </div>
          <div className="p-4">
            <LiveLocationMap points={mapPoints} height={360} />
            {mapSnapshotUrl ? (
              <figure className="mt-4">
                <img className="w-full rounded-2xl border border-[var(--border)]" src={mapSnapshotUrl} alt="لقطة الخريطة الملتقطة مع استجابة الموظف" />
                <figcaption className="muted mt-2 text-xs">لقطة الخريطة الأصلية المحفوظة مع الاستجابة (رابط خاص قصير الصلاحية).</figcaption>
              </figure>
            ) : (
              <button type="button" className="btn-secondary mt-4" onClick={() => void loadMapSnapshot()} disabled={mapUrlCmd.isPending}>
                <MapPin className="size-4" aria-hidden="true" />
                {mapUrlCmd.isPending ? 'جارٍ تحميل اللقطة…' : 'عرض لقطة الخريطة المحفوظة'}
              </button>
            )}
            {mapUrlCmd.isError ? <ErrorBanner message="لا توجد لقطة خريطة متاحة أو انتهت مدة الاحتفاظ بها." /> : null}
            {latest?.addressAr ? (
              <p className="mt-3 flex items-start gap-2 text-sm">
                <MapPin className="mt-0.5 size-4 shrink-0 text-[var(--brand-primary)]" />
                <span>
                  الموظف قريب من: <strong>{latest.addressAr}</strong>
                  {latestAccuracy !== null ? <> — دقة تقريبية {Math.round(latestAccuracy)} متر</> : null}
                </span>
              </p>
            ) : latestAccuracy !== null ? (
              <p className="muted mt-3 text-sm">إحداثيات مسجّلة بدقة تقريبية {Math.round(latestAccuracy)} متر (لم يتوفّر عنوان نصي).</p>
            ) : null}
          </div>
        </article>
      ) : (
        <EmptyState title="لم يصل موقع بعد" description="بانتظار استجابة الموظف وإرسال موقعه." />
      )}

      {/* V17 §9: video section permanently removed — location-only. */}
    </div>
  );
}

function Stat({ icon: Icon, label, value }: { icon: typeof Clock; label: string; value: string }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-3">
      <span className="muted flex items-center gap-1 text-[11px]">
        <Icon className="size-3" aria-hidden="true" />
        {label}
      </span>
      <strong className="mt-1 block text-sm">{value}</strong>
    </div>
  );
}
