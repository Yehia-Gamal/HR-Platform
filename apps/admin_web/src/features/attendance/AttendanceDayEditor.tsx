import type { AttendanceStatementDay } from '@ahla/shared-contracts';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  AlertCircle,
  Briefcase,
  Calendar,
  Check,
  CheckCircle2,
  Clock,
  Compass,
  HeartHandshake,
  MapPin,
  Pencil,
  RotateCcw,
  Send,
  Sparkles,
  Sun,
  Umbrella,
  XCircle,
} from 'lucide-react';
import { useEffect, useId, useState } from 'react';
import { rpc } from '../../core/rpc';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { getDisplayNote } from './attendanceShared';
import { useAuth } from '../auth/AuthProvider';

interface DayTypeConfig {
  key: string;
  label: string;
  desc: string;
  icon: typeof Briefcase;
  color: string;
  bgColor: string;
}

const DAY_TYPE_CONFIGS: DayTypeConfig[] = [
  {
    key: 'work',
    label: 'يوم عمل (حاضر)',
    desc: 'تسجيل أو تعديل ساعات وأوقات الحضور والانصراف',
    icon: Briefcase,
    color: 'text-emerald-700 dark:text-emerald-300',
    bgColor: 'bg-emerald-50 dark:bg-emerald-950/40 border-emerald-300 dark:border-emerald-800',
  },
  {
    key: 'leave',
    label: 'إجازة معتمدة',
    desc: 'سنوية، عارضة، مرضية، أو بدون راتب',
    icon: Umbrella,
    color: 'text-indigo-700 dark:text-indigo-300',
    bgColor: 'bg-indigo-50 dark:bg-indigo-950/40 border-indigo-300 dark:border-indigo-800',
  },
  {
    key: 'mission',
    label: 'مأمورية عمل',
    desc: 'مهمة رسمية ميدانية أو إدارية',
    icon: Compass,
    color: 'text-sky-700 dark:text-sky-300',
    bgColor: 'bg-sky-50 dark:bg-sky-950/40 border-sky-300 dark:border-sky-800',
  },
  {
    key: 'convoy',
    label: 'قافلة خيرية ومساعدات',
    desc: 'سفر ومساعدات للأسر المستحقة (أسقف، مياه، كفالات) — يوم عمل خارجي',
    icon: HeartHandshake,
    color: 'text-purple-700 dark:text-purple-300',
    bgColor: 'bg-purple-50 dark:bg-purple-950/40 border-purple-300 dark:border-purple-800',
  },
  {
    key: 'fundraising',
    label: 'يوم ترفيهي (فاندي)',
    desc: 'يوم ترفيهي للموظفين بتنظيم الإدارة (فيلا/سفر ترفيهي) — يُحسب يوم عمل كامل',
    icon: Sparkles,
    color: 'text-pink-700 dark:text-pink-300',
    bgColor: 'bg-pink-50 dark:bg-pink-950/40 border-pink-300 dark:border-pink-800',
  },
  {
    key: 'rest',
    label: 'راحة أسبوعية',
    desc: 'يوم عطلة وراحة مجدولة للموظف',
    icon: Sun,
    color: 'text-slate-700 dark:text-slate-300',
    bgColor: 'bg-slate-50 dark:bg-slate-900/40 border-slate-300 dark:border-slate-800',
  },
  {
    key: 'holiday',
    label: 'عطلة رسمية',
    desc: 'إجازة رسمية معتمدة للدولة/المؤسسة',
    icon: Calendar,
    color: 'text-amber-700 dark:text-amber-300',
    bgColor: 'bg-amber-50 dark:bg-amber-950/40 border-amber-300 dark:border-amber-800',
  },
  {
    key: 'absent',
    label: 'غائب دون إذن',
    desc: 'تسجيل أو تأكيد غياب غير مبرر مع الخصم',
    icon: XCircle,
    color: 'text-rose-700 dark:text-rose-300',
    bgColor: 'bg-rose-50 dark:bg-rose-950/40 border-rose-300 dark:border-rose-800',
  },
];

const LEAVE_TYPES = [
  ['annual', 'إجازة سنوية (اعتيادية)'],
  ['casual', 'إجازة عارضة'],
  ['sick', 'إجازة مرضية'],
  ['unpaid', 'إجازة بدون راتب'],
  ['weekly_rest_comp', 'بدل راحة أسبوعية (لا تُخصم من الرصيد)'],
] as const;

const DEFAULT_LEAVE_TYPE: Record<string, string> = {
  leave: 'annual',
  absent: 'unpaid',
};

const QUICK_HOURS_PRESETS = [
  { label: 'دوام كامل (8 س)', in: '09:00', out: '17:00' },
  { label: 'دوام مبكر (8 س)', in: '08:00', out: '16:00' },
  { label: 'نصف دوام (4 س)', in: '09:00', out: '13:00' },
  { label: 'دوام ممتد (10 س)', in: '08:00', out: '18:00' },
];

const PRESET_REASONS: Record<string, string[]> = {
  work: ['تعديل ساعات العمل المعتمدة', 'تصحيح وقت الحضور والانصراف', 'إضافة بصمة منسية', 'دوام كامل معتمد'],
  leave: ['إجازة اعتيادية معتمدة', 'إجازة مرضية بتقرير طبي', 'إجازة طارئة بموافقة الإدارة', 'إجازة معتمدة بأثر رجعي'],
  mission: ['مأمورية عمل ميدانية', 'مأمورية إدارية رسمية', 'انتداب رسمي خارج المقر'],
  convoy: ['مشاركة في قافلة خيرية للأسر', 'حفر وصلات مياه ومساعدات أسر مستحقة', 'بناء أسقف وتسليم كفالات للأسر المستحقة', 'سفر وزيارة ميدانية للأسر'],
  fundraising: ['مشاركة في يوم ترفيهي للموظفين (فاندي)', 'رحلة ترفيهية للموظفين معتمدة من الإدارة', 'نشاط ترفيهي جماعي للموظفين'],
  holiday: ['عطلة رسمية بالدولة', 'إجازة رسمية معتمدة'],
  rest: ['راحة أسبوعية معتمدة', 'تبديل يوم راحة'],
  absent: ['تأكيد غياب بدون إذن', 'غياب غير مبرر'],
};

interface MarkDayOption {
  value: string;
  category: 'operational' | 'leave';
  label: string;
  sublabel: string;
  defaultReason: string;
  suggestions: string[];
  icon: typeof Briefcase;
  color: string;
  badgeBg: string;
}

const MARK_DAY_OPTIONS: MarkDayOption[] = [
  {
    value: 'mission',
    category: 'operational',
    label: 'مأمورية عمل رسمية',
    sublabel: 'مهمة عمل ميدانية أو إدارية خارج المقر',
    defaultReason: 'اعتماد مأمورية عمل رسمية',
    suggestions: ['مأمورية عمل ميدانية', 'مأمورية إدارية رسمية', 'انتداب وتكليف خارج المقر'],
    icon: Compass,
    color: 'text-sky-600 dark:text-sky-400',
    badgeBg: 'bg-sky-50 dark:bg-sky-950/40 border-sky-300 dark:border-sky-800',
  },
  {
    value: 'convoy',
    category: 'operational',
    label: 'قافلة خيرية ومساعدات',
    sublabel: 'سفر ومساعدات للأسر المستحقة (أسقف، مياه، كفالات)',
    defaultReason: 'مشاركة في قافلة خيرية وتوزيع مساعدات للأسر المستحقة',
    suggestions: ['مشاركة في قافلة خيرية للأسر', 'حملة بناء أسقف ووصلات مياه', 'توزيع كفالات ومساعدات ميدانية'],
    icon: HeartHandshake,
    color: 'text-purple-600 dark:text-purple-400',
    badgeBg: 'bg-purple-50 dark:bg-purple-950/40 border-purple-300 dark:border-purple-800',
  },
  {
    value: 'fundraising',
    category: 'operational',
    label: 'يوم ترفيهي (فاندي / Fun Day)',
    sublabel: 'نشاط ترفيهي جماعي معتمد للموظفين',
    defaultReason: 'مشاركة في يوم ترفيهي للموظفين (فاندي)',
    suggestions: ['مشاركة في يوم ترفيهي للموظفين (فاندي)', 'رحلة ترفيهية معتمدة من الإدارة', 'نشاط ترفيهي جماعي للموظفين'],
    icon: Sparkles,
    color: 'text-pink-600 dark:text-pink-400',
    badgeBg: 'bg-pink-50 dark:bg-pink-950/40 border-pink-300 dark:border-pink-800',
  },
  {
    value: 'annual',
    category: 'leave',
    label: 'إجازة سنوية (اعتيادية)',
    sublabel: 'تُخصم من رصيد الإجازات السنوية للموظف',
    defaultReason: 'إجازة سنوية اعتيادية معتمدة',
    suggestions: ['إجازة سنوية اعتيادية معتمدة', 'إجازة سنوية لظرف عائلي', 'إجازة سنوية بأثر رجعي'],
    icon: Umbrella,
    color: 'text-indigo-600 dark:text-indigo-400',
    badgeBg: 'bg-indigo-50 dark:bg-indigo-950/40 border-indigo-300 dark:border-indigo-800',
  },
  {
    value: 'casual',
    category: 'leave',
    label: 'إجازة عارضة',
    sublabel: 'إجازة طارئة للموظف تخصم من رصيد العارضة',
    defaultReason: 'إجازة عارضة طارئة معتمدة',
    suggestions: ['إجازة عارضة طارئة معتمدة', 'ظرف قهري طارئ', 'عارضة بموافقة المدير'],
    icon: Umbrella,
    color: 'text-amber-600 dark:text-amber-400',
    badgeBg: 'bg-amber-50 dark:bg-amber-950/40 border-amber-300 dark:border-amber-800',
  },
  {
    value: 'unpaid',
    category: 'leave',
    label: 'إجازة بدون راتب',
    sublabel: 'إجازة خاصة غير مدفوعة الأجر',
    defaultReason: 'إجازة بدون راتب معتمدة',
    suggestions: ['إجازة خاصة بدون راتب', 'غياب مبرر بدون راتب', 'ظرف خاص غير مدفوع'],
    icon: Calendar,
    color: 'text-slate-600 dark:text-slate-400',
    badgeBg: 'bg-slate-50 dark:bg-slate-900/40 border-slate-300 dark:border-slate-800',
  },
  {
    value: 'weekly_rest_comp',
    category: 'leave',
    label: 'بدل راحة أسبوعية',
    sublabel: 'تعويض عن عمل بيوم راحة (لا تُخصم من الرصيد)',
    defaultReason: 'بدل راحة أسبوعية معتمدة',
    suggestions: ['تعويض عن يوم عمل في راحة أسبوعية', 'بدل راحة معتمدة من الإدارة', 'تبديل يوم راحة أسبوعية'],
    icon: Sun,
    color: 'text-emerald-600 dark:text-emerald-400',
    badgeBg: 'bg-emerald-50 dark:bg-emerald-950/40 border-emerald-300 dark:border-emerald-800',
  },
];

function getMarkRequestTitle(type: string, dayName: string, date: string): string {
  const opt = MARK_DAY_OPTIONS.find((o) => o.value === type);
  const typeName = opt ? opt.label.split('(')[0].trim() : 'اعتماد يوم';
  return `طلب ${typeName} - ${dayName} (${date})`;
}

export function AttendanceDayEditor({ employeeId, day }: { employeeId: string; day: AttendanceStatementDay }) {
  const auth = useAuth();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [markOpen, setMarkOpen] = useState(false);

  const roles = auth?.access?.roles ?? [];
  const isExec = roles.includes('executive-director') || roles.includes('executive') || (auth?.access?.displayName?.includes('محمد يوسف') ?? false);
  const canAdminEdit =
    !isExec &&
    (roles.includes('hr-manager') ||
      roles.includes('hr-specialist') ||
      roles.includes('executive-secretary') ||
      roles.includes('admin') ||
      roles.includes('super-admin') ||
      (auth?.access?.employeeCode?.includes('01154869616') ?? false));

  const [dayType, setDayType] = useState<string>((day.adminOverride?.dayType as string | undefined) ?? 'work');
  const [leaveType, setLeaveType] = useState<string>(
    day.adminOverride?.leaveType ??
      (day.adminOverride?.dayType === 'leave' || day.adminOverride?.dayType === 'absent' ? DEFAULT_LEAVE_TYPE[day.adminOverride.dayType] : 'annual'),
  );
  const [checkIn, setCheckIn] = useState(day.checkIn?.slice(0, 5) ?? '09:00');
  const [checkOut, setCheckOut] = useState(day.checkOut?.slice(0, 5) ?? '17:00');
  const [clearCheckIn, setClearCheckIn] = useState(false);
  const [clearCheckOut, setClearCheckOut] = useState(false);
  const [reason, setReason] = useState(day.adminOverride?.reason ?? 'تعديل ساعات وحضور معتمد');
  const [notes, setNotes] = useState(day.adminOverride?.notes ?? '');

  // طلب اعتماد مبرر / حالة اليوم
  const [markType, setMarkType] = useState<string>('mission');
  const [markReason, setMarkReason] = useState('اعتماد مأمورية عمل رسمية');
  const [markLocation, setMarkLocation] = useState('');

  // إعادة ضبط الحقول عند تغيير اليوم
  useEffect(() => {
    const existingType = (day.adminOverride?.dayType as string | undefined) ?? 'work';
    setDayType(existingType);
    setLeaveType(day.adminOverride?.leaveType ?? (existingType === 'leave' || existingType === 'absent' ? DEFAULT_LEAVE_TYPE[existingType] : 'annual'));
    setCheckIn(day.checkIn?.slice(0, 5) ?? '09:00');
    setCheckOut(day.checkOut?.slice(0, 5) ?? '17:00');
    setReason(day.adminOverride?.reason ?? 'تعديل ساعات وحضور معتمد');
    setNotes(day.adminOverride?.notes ?? '');
    setClearCheckIn(false);
    setClearCheckOut(false);
  }, [day]);

  // حفظ التعديل الإداري
  const saveMutation = useMutation({
    mutationFn: () =>
      rpc('set_employee_attendance_day_admin', {
        p_employee_id: employeeId,
        p_work_date: day.date,
        p_day_type: dayType,
        p_check_in: dayType === 'work' && !clearCheckIn ? checkIn : null,
        p_check_out: dayType === 'work' && !clearCheckOut ? checkOut : null,
        p_clear_check_in: dayType !== 'work' || clearCheckIn,
        p_clear_check_out: dayType !== 'work' || clearCheckOut,
        p_reason: reason.trim() || 'اعتماد الحالة',
        p_notes: notes.trim() || null,
        p_leave_type: dayType === 'leave' || dayType === 'absent' ? leaveType || DEFAULT_LEAVE_TYPE[dayType] : null,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  // إلغاء التعديل الإداري والعودة لاحتساب النظام الأصلي
  const clearMutation = useMutation({
    mutationFn: () =>
      rpc('clear_employee_attendance_day_admin', {
        p_employee_id: employeeId,
        p_work_date: day.date,
      }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      setOpen(false);
    },
  });

  // طلب اعتماد مبرر / حالة اليوم بموافقة المدير
  const markMutation = useMutation({
    mutationFn: () => {
      const isOperational = ['mission', 'convoy', 'fundraising'].includes(markType);
      return rpc('submit_employee_day_mark', {
        p_employee_id: employeeId,
        p_request_type: isOperational ? markType : 'leave',
        p_title: getMarkRequestTitle(markType, day.dayNameAr, day.date),
        p_reason: markReason.trim() || 'طلب اعتماد ومبرر إداري ليوم العمل',
        p_payload: {
          startDate: day.date,
          endDate: day.date,
          ...(isOperational ? { location: markLocation.trim() } : { leaveType: markType }),
          dayMark: true,
        },
      });
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['attendance-statement', employeeId] });
      await queryClient.invalidateQueries({ queryKey: ['requests'] });
      setMarkOpen(false);
    },
  });

  // حساب ساعات العمل تقريبياً
  const calculatedHours = (() => {
    if (dayType !== 'work' || clearCheckIn || clearCheckOut || !checkIn || !checkOut) return null;
    const [inH, inM] = checkIn.split(':').map(Number);
    const [outH, outM] = checkOut.split(':').map(Number);
    if (isNaN(inH) || isNaN(inM) || isNaN(outH) || isNaN(outM)) return null;
    const totalMin = outH * 60 + outM - (inH * 60 + inM);
    if (totalMin <= 0) return null;
    return (totalMin / 60).toFixed(1);
  })();

  const clearCheckInId = useId();
  const clearCheckOutId = useId();

  return (
    <>
      <div className="flex items-center justify-end gap-1.5 whitespace-nowrap">
        {canAdminEdit && (
          <button
            type="button"
            className="inline-flex items-center gap-1 rounded-md border border-[var(--primary)]/30 bg-[var(--primary)]/10 px-2 py-1 text-xs font-bold text-[var(--primary)] transition hover:bg-[var(--primary)]/20 shadow-xs whitespace-nowrap"
            onClick={() => setOpen(true)}
            title="تعديل حالة اليوم أو ساعات وأأوقات الدوام إدارياً"
          >
            <Pencil className="size-3" aria-hidden="true" />
            <span>تعديل</span>
          </button>
        )}
        <button
          type="button"
          className="inline-flex items-center gap-1 rounded-md border border-sky-500/30 bg-sky-500/10 px-2 py-1 text-xs font-bold text-sky-600 dark:text-sky-400 transition hover:bg-sky-500/20 shadow-xs whitespace-nowrap"
          onClick={() => {
            const opt = MARK_DAY_OPTIONS.find((o) => o.value === markType);
            setMarkReason(opt?.defaultReason ?? 'اعتماد مأمورية عمل رسمية');
            setMarkOpen(true);
          }}
          title="إرسال طلب اعتماد أو مبرر للمدير المباشر لرفع الغياب"
        >
          <Send className="size-3 text-sky-500" aria-hidden="true" />
          <span>طلب اعتماد</span>
        </button>
      </div>

      {open ? (
        <DialogOverlay title={`تعديل يوم ${day.dayNameAr} (${day.date})`} onClose={() => setOpen(false)} maxWidth="max-w-2xl">
          <div className="space-y-3.5 text-end">
            {/* إشعار وجود تعديل إداري سابق مع زر الإلغاء */}
            {day.adminOverride ? (
              <div className="flex flex-col gap-2 rounded-xl border border-amber-300 bg-amber-50/80 p-3 text-xs dark:border-amber-800/80 dark:bg-amber-950/30 sm:flex-row sm:items-center sm:justify-between">
                <div className="flex items-start gap-2 text-amber-900 dark:text-amber-200">
                  <AlertCircle className="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400" />
                  <div>
                    <span className="font-bold">بيانات هذا اليوم معدّلة إدارياً: </span>
                    <span>
                      الحالة: <b>{DAY_TYPE_CONFIGS.find((c) => c.key === day.adminOverride?.dayType)?.label ?? day.adminOverride.dayType}</b>
                      {getDisplayNote(day.adminOverride.reason) ? ` · السبب: ${getDisplayNote(day.adminOverride.reason)}` : ''}
                    </span>
                  </div>
                </div>
                <button
                  type="button"
                  className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-2.5 py-1.5 text-xs font-bold text-rose-700 transition hover:bg-rose-100 dark:border-rose-800 dark:bg-rose-950/50 dark:text-rose-300 dark:hover:bg-rose-900/50"
                  disabled={clearMutation.isPending}
                  onClick={() => {
                    if (window.confirm('هل تريد إلغاء تعديل هذا اليوم والعودة لاحتساب النظام الأصلي؟')) {
                      clearMutation.mutate();
                    }
                  }}
                  title="حذف التعديل والعودة التلقائية لحسابات النظام"
                >
                  <RotateCcw className="size-3.5" />
                  <span>{clearMutation.isPending ? 'جارٍ الإلغاء…' : 'إلغاء التعديل والعودة للنظام'}</span>
                </button>
              </div>
            ) : null}

            {/* 1. اختيار نوع اليوم */}
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">اختر حالة اليوم الجديدة</label>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {DAY_TYPE_CONFIGS.map((cfg) => {
                  const Icon = cfg.icon;
                  const isSelected = dayType === cfg.key;
                  return (
                    <button
                      key={cfg.key}
                      type="button"
                      onClick={() => {
                        setDayType(cfg.key);
                        if (cfg.key === 'leave' || cfg.key === 'absent') {
                          setLeaveType(DEFAULT_LEAVE_TYPE[cfg.key]);
                        }
                        const presets = PRESET_REASONS[cfg.key];
                        if (presets && presets.length > 0) {
                          setReason(presets[0]);
                        }
                      }}
                      className={`relative flex flex-col justify-between min-h-[58px] rounded-xl border p-2 text-end transition ${
                        isSelected
                          ? `${cfg.bgColor} ring-2 ring-[var(--primary)] shadow-sm`
                          : 'border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]'
                      }`}
                    >
                      <div className="flex w-full items-center justify-between">
                        <Icon className={`size-4 ${cfg.color}`} />
                        {isSelected ? (
                          <CheckCircle2 className="size-4 text-[var(--primary)]" />
                        ) : (
                          <div className="size-3.5 rounded-full border border-[var(--border)]" />
                        )}
                      </div>
                      <span className="text-xs font-bold leading-tight text-[var(--text-primary)] mt-1 truncate block w-full">{cfg.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* 2. تفاصيل الإجازة إن اختيرت */}
            {dayType === 'leave' || dayType === 'absent' ? (
              <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-subtle)] p-2.5 space-y-1">
                <label className="block text-xs font-bold text-[var(--text-secondary)]">نوع الإجازة (يتم الخصم طبقاً للائحة)</label>
                <select className="input w-full text-xs" value={leaveType} onChange={(e) => setLeaveType(e.target.value)}>
                  {LEAVE_TYPES.map(([val, lbl]) => (
                    <option key={val} value={val}>
                      {lbl}
                    </option>
                  ))}
                </select>
              </div>
            ) : null}

            {/* 3. تفاصيل ساعات وأوقات العمل عند اختيار "يوم عمل" */}
            {dayType === 'work' ? (
              <div className="space-y-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-subtle)] p-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-[var(--text-secondary)] flex items-center gap-1.5">
                    <Clock className="size-3.5 text-[var(--primary)]" />
                    ضبط ساعات وأوقات الدوام
                  </span>
                  {calculatedHours ? (
                    <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-bold text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300">
                      إجمالي العمل: {calculatedHours} ساعة
                    </span>
                  ) : null}
                </div>

                {/* أزرار سريعة لساعات العمل - مصفوفة متساوية 4 أعمدة */}
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  {QUICK_HOURS_PRESETS.map((p) => {
                    const isActive = checkIn === p.in && checkOut === p.out && !clearCheckIn && !clearCheckOut;
                    return (
                      <button
                        key={p.label}
                        type="button"
                        className={`flex items-center justify-center gap-1 rounded-lg border py-1.5 px-1.5 text-xs font-bold transition ${
                          isActive
                            ? 'border-[var(--primary)] bg-[var(--primary)]/15 text-[var(--primary)] shadow-xs'
                            : 'border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]'
                        }`}
                        onClick={() => {
                          setCheckIn(p.in);
                          setCheckOut(p.out);
                          setClearCheckIn(false);
                          setClearCheckOut(false);
                        }}
                      >
                        <Clock className="size-3 shrink-0 opacity-70" />
                        <span>{p.label}</span>
                      </button>
                    );
                  })}
                </div>

                <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
                  <div
                    className={`space-y-1 rounded-lg border p-2.5 transition ${clearCheckIn ? 'border-[var(--border)] bg-[var(--surface-muted)]/50 opacity-60' : 'border-[var(--border)] bg-[var(--surface)]'}`}
                  >
                    <div className="flex items-center justify-between">
                      <label className="text-xs font-bold text-[var(--text-secondary)]">وقت الحضور</label>
                      <label
                        htmlFor={clearCheckInId}
                        className="flex items-center gap-1.5 text-[11px] text-[var(--text-muted)] cursor-pointer select-none hover:text-[var(--text-primary)]"
                      >
                        <input
                          id={clearCheckInId}
                          type="checkbox"
                          className="rounded accent-[var(--primary)]"
                          checked={clearCheckIn}
                          onChange={(e) => setClearCheckIn(e.target.checked)}
                        />
                        <span>بدون بصمة حضور</span>
                      </label>
                    </div>
                    <input
                      type="time"
                      className="input w-full font-mono text-sm tracking-wider font-bold text-center"
                      value={checkIn}
                      disabled={clearCheckIn}
                      onChange={(e) => setCheckIn(e.target.value)}
                    />
                  </div>

                  <div
                    className={`space-y-1 rounded-lg border p-2.5 transition ${clearCheckOut ? 'border-[var(--border)] bg-[var(--surface-muted)]/50 opacity-60' : 'border-[var(--border)] bg-[var(--surface)]'}`}
                  >
                    <div className="flex items-center justify-between">
                      <label className="text-xs font-bold text-[var(--text-secondary)]">وقت الانصراف</label>
                      <label
                        htmlFor={clearCheckOutId}
                        className="flex items-center gap-1.5 text-[11px] text-[var(--text-muted)] cursor-pointer select-none hover:text-[var(--text-primary)]"
                      >
                        <input
                          id={clearCheckOutId}
                          type="checkbox"
                          className="rounded accent-[var(--primary)]"
                          checked={clearCheckOut}
                          onChange={(e) => setClearCheckOut(e.target.checked)}
                        />
                        <span>بدون بصمة انصراف</span>
                      </label>
                    </div>
                    <input
                      type="time"
                      className="input w-full font-mono text-sm tracking-wider font-bold text-center"
                      value={checkOut}
                      disabled={clearCheckOut}
                      onChange={(e) => setCheckOut(e.target.value)}
                    />
                  </div>
                </div>
              </div>
            ) : null}

            {/* 4. سبب التعديل - مصفوفة متساوية 4 أعمدة */}
            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">سبب التعديل</label>
              {(PRESET_REASONS[dayType] ?? []).length > 0 ? (
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-1.5">
                  {(PRESET_REASONS[dayType] ?? []).map((preset) => {
                    const isActive = reason === preset;
                    return (
                      <button
                        key={preset}
                        type="button"
                        className={`truncate rounded-lg border py-1.5 px-2 text-xs font-medium text-center transition ${
                          isActive
                            ? 'border-[var(--primary)] bg-[var(--primary)]/15 text-[var(--primary)] font-bold shadow-xs'
                            : 'border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                        }`}
                        title={preset}
                        onClick={() => setReason(preset)}
                      >
                        {preset}
                      </button>
                    );
                  })}
                </div>
              ) : null}
              <input
                className="input w-full text-xs"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="اكتب سبب التعديل أو اختر من الأسباب الجاهزة أعلاه…"
              />
            </div>

            {/* 5. ملاحظات إضافية */}
            <div className="space-y-1">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">ملاحظات إدارية (اختيارية)</label>
              <textarea
                className="input min-h-12 w-full text-xs resize-none"
                rows={2}
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="أي توضيحات أو أرقام قرارات تدعم التعديل…"
              />
            </div>

            {saveMutation.isError ? (
              <p className="rounded-lg bg-[var(--danger-soft)] p-2.5 text-xs font-bold text-[var(--danger)]">{safeErrorMessage(saveMutation.error)}</p>
            ) : null}

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border)]">
              <button type="button" className="btn-secondary text-xs" onClick={() => setOpen(false)}>
                إلغاء
              </button>
              <button
                type="button"
                className="btn-primary text-xs flex items-center gap-1.5"
                disabled={saveMutation.isPending}
                onClick={() => saveMutation.mutate()}
              >
                <Check className="size-3.5" />
                <span>{saveMutation.isPending ? 'جارٍ الحفظ…' : 'حفظ التعديل'}</span>
              </button>
            </div>
          </div>
        </DialogOverlay>
      ) : null}

      {/* مودال طلب اعتماد مبرر / حالة يوم بموافقة المدير */}
      {markOpen ? (
        <DialogOverlay title={`طلب اعتماد حالة يوم ${day.dayNameAr} (${day.date})`} onClose={() => setMarkOpen(false)} maxWidth="max-w-2xl">
          <form
            className="space-y-3.5 text-end"
            onSubmit={(e) => {
              e.preventDefault();
              markMutation.mutate();
            }}
          >
            <div className="rounded-xl border border-sky-200 bg-sky-50/70 p-2.5 text-xs text-sky-900 dark:border-sky-800/80 dark:bg-sky-950/40 dark:text-sky-200 flex items-start gap-2.5">
              <Send className="size-4 shrink-0 mt-0.5 text-sky-600 dark:text-sky-400" />
              <div>
                <p className="font-bold">طلب اعتماد ومبرر إداري</p>
                <p className="mt-0.5 text-[11px] leading-relaxed text-sky-800/90 dark:text-sky-300/90">
                  يُرسل هذا الطلب إلى المدير المباشر للاعتماد رسمياً، وتُحدّث حالة اليوم تلقائياً فور الموافقة ليزول الغياب أو الخصم.
                </p>
              </div>
            </div>

            {/* اختيار نوع اليوم المطلوب - مقسم بتنسيق متوازن */}
            <div className="space-y-3">
              {/* مهام وتكليفات عمل */}
              <div className="space-y-1.5">
                <span className="text-[11px] font-bold text-[var(--text-muted)] flex items-center gap-1">
                  <Briefcase className="size-3 text-sky-500" />
                  مهام وتكليفات عمل (تُحسب يوم عمل كامل):
                </span>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  {MARK_DAY_OPTIONS.filter((o) => o.category === 'operational').map((opt) => {
                    const Icon = opt.icon;
                    const isSelected = markType === opt.value;
                    return (
                      <button
                        key={opt.value}
                        type="button"
                        onClick={() => {
                          setMarkType(opt.value);
                          setMarkReason(opt.defaultReason);
                        }}
                        className={`flex flex-col justify-between rounded-xl border p-2.5 text-end transition ${
                          isSelected
                            ? `${opt.badgeBg} ring-2 ring-[var(--primary)] shadow-sm`
                            : 'border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]'
                        }`}
                      >
                        <div className="flex w-full items-center justify-between">
                          <Icon className={`size-4 ${opt.color}`} />
                          {isSelected ? (
                            <CheckCircle2 className="size-3.5 text-[var(--primary)] shrink-0" />
                          ) : (
                            <div className="size-3 rounded-full border border-[var(--border)]" />
                          )}
                        </div>
                        <div className="mt-2">
                          <span className="text-xs font-bold text-[var(--text-primary)] block leading-tight">{opt.label}</span>
                          <p className="text-[10px] text-[var(--text-muted)] line-clamp-1 mt-0.5">{opt.sublabel}</p>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* إجازات وبدائل معتمدة */}
              <div className="space-y-1.5">
                <span className="text-[11px] font-bold text-[var(--text-muted)] flex items-center gap-1">
                  <Umbrella className="size-3 text-indigo-500" />
                  إجازات وبدائل راحة معتمدة:
                </span>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  {MARK_DAY_OPTIONS.filter((o) => o.category === 'leave').map((opt) => {
                    const Icon = opt.icon;
                    const isSelected = markType === opt.value;
                    return (
                      <button
                        key={opt.value}
                        type="button"
                        onClick={() => {
                          setMarkType(opt.value);
                          setMarkReason(opt.defaultReason);
                        }}
                        className={`flex flex-col justify-between rounded-xl border p-2 text-end transition ${
                          isSelected
                            ? `${opt.badgeBg} ring-2 ring-[var(--primary)] shadow-sm`
                            : 'border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]'
                        }`}
                      >
                        <div className="flex w-full items-center justify-between">
                          <Icon className={`size-3.5 ${opt.color}`} />
                          {isSelected ? (
                            <CheckCircle2 className="size-3.5 text-[var(--primary)] shrink-0" />
                          ) : (
                            <div className="size-3 rounded-full border border-[var(--border)]" />
                          )}
                        </div>
                        <div className="mt-1.5">
                          <span className="text-xs font-bold text-[var(--text-primary)] block leading-tight truncate">{opt.label}</span>
                          <p className="text-[9px] text-[var(--text-muted)] line-clamp-1 mt-0.5">{opt.sublabel}</p>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>

            {['mission', 'convoy', 'fundraising'].includes(markType) ? (
              <div className="space-y-1">
                <label className="block text-xs font-bold text-[var(--text-secondary)] flex items-center gap-1.5">
                  <MapPin className="size-3.5 text-[var(--primary)]" />
                  <span>المكان / الجهة الخارجية (مطلوب)</span>
                </label>
                <input
                  className="input w-full text-xs"
                  value={markLocation}
                  required
                  onChange={(e) => setMarkLocation(e.target.value)}
                  placeholder={
                    markType === 'convoy'
                      ? 'مثال: قرى الفيوم، قافلة أسقف ومياه ومساعدات للأسر المستحقة…'
                      : markType === 'fundraising'
                        ? 'مثال: فيلا سقارة، منتجع وادي النخيل، مكان الترفيه…'
                        : 'مثال: مقر الفرع، زيارة فرع، مأمورية عمل خارجية…'
                  }
                />
              </div>
            ) : null}

            <div className="space-y-1.5">
              <label className="block text-xs font-bold text-[var(--text-secondary)]">السبب والتوضيح للمدير المباشر</label>
              {/* أزرار سريعة للأسباب */}
              {(() => {
                const currentOpt = MARK_DAY_OPTIONS.find((o) => o.value === markType);
                const suggestions = currentOpt?.suggestions ?? [];
                if (!suggestions.length) return null;
                return (
                  <div className="flex flex-wrap gap-1.5">
                    {suggestions.map((sug) => {
                      const isActive = markReason === sug;
                      return (
                        <button
                          key={sug}
                          type="button"
                          className={`rounded-lg border px-2 py-1 text-[11px] font-medium transition ${
                            isActive
                              ? 'border-[var(--primary)] bg-[var(--primary)]/15 text-[var(--primary)] font-bold shadow-xs'
                              : 'border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                          }`}
                          onClick={() => setMarkReason(sug)}
                        >
                          {sug}
                        </button>
                      );
                    })}
                  </div>
                );
              })()}
              <input
                className="input w-full text-xs"
                value={markReason}
                required
                onChange={(e) => setMarkReason(e.target.value)}
                placeholder="اكتب سبب ومبرر الطلب بدقة…"
              />
            </div>

            {markMutation.isError ? (
              <p className="rounded-lg bg-[var(--danger-soft)] p-2.5 text-xs font-bold text-[var(--danger)]">{safeErrorMessage(markMutation.error)}</p>
            ) : null}

            <div className="flex justify-end gap-2 pt-2 border-t border-[var(--border)]">
              <button type="button" className="btn-secondary text-xs" onClick={() => setMarkOpen(false)}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary text-xs flex items-center gap-1.5" disabled={markMutation.isPending}>
                <Send className="size-3.5" />
                <span>{markMutation.isPending ? 'جارٍ الإرسال…' : 'إرسال الطلب للاعتماد'}</span>
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}
    </>
  );
}
