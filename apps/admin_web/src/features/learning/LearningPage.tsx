import { useMemo, useState, type FormEvent } from 'react';
import { Award, BookOpen, CheckCircle2, GraduationCap, Loader2, Pencil, Plus, RefreshCw, UserPlus } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import {
  useEnrollEmployee,
  useLearningCatalog,
  useTransitionEnrollment,
  useUpsertCourse,
  type CourseFormInput,
  type LearningCourse,
  type LearningEmployee,
  type LearningEnrollment,
} from './useLearning';

const CATEGORY_ORDER = ['all', 'general', 'technical', 'management', 'compliance'] as const;

const CATEGORY_LABELS: Record<string, string> = {
  general: 'عام',
  technical: 'تقني',
  management: 'إداري',
  compliance: 'امتثال',
};

const DELIVERY_LABELS: Record<string, string> = {
  online: 'عن بُعد',
  onsite: 'حضوري',
  hybrid: 'هجين',
  self_paced: 'ذاتي',
};

const ENROLLMENT_LABELS: Record<LearningEnrollment['status'], string> = {
  enrolled: 'مسجّل',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتمل',
  failed: 'فشل',
  cancelled: 'ملغي',
};

const ENROLLMENT_TONE: Record<LearningEnrollment['status'], string> = {
  enrolled: 'info',
  in_progress: 'in_progress',
  completed: 'finalized',
  failed: 'failed',
  cancelled: 'cancelled',
};

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

export function LearningPage() {
  const catalog = useLearningCatalog();
  const upsertCourse = useUpsertCourse();
  const enrollEmployee = useEnrollEmployee();
  const transitionEnrollment = useTransitionEnrollment();
  const { toast } = useToast();

  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<string>('all');
  const [courseDialog, setCourseDialog] = useState<{ course: LearningCourse | null } | null>(null);
  const [enrollTarget, setEnrollTarget] = useState<LearningCourse | null>(null);

  const courses = useMemo(() => catalog.data?.courses ?? [], [catalog.data]);
  const enrollments = useMemo(() => catalog.data?.enrollments ?? [], [catalog.data]);
  const employees = useMemo(() => catalog.data?.employees ?? [], [catalog.data]);

  const activeCourses = courses.filter((c) => c.active).length;
  const mandatoryCount = courses.filter((c) => c.mandatory).length;
  const totalEnrollments = courses.reduce((sum, c) => sum + c.enrollments, 0);
  const completedEnrollments = enrollments.filter((e) => e.status === 'completed').length;

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return courses
      .filter((c) => {
        const matchSearch = !q || c.title.toLowerCase().includes(q) || c.code.toLowerCase().includes(q);
        const matchCategory = category === 'all' || c.category === category;
        return matchSearch && matchCategory;
      })
      .sort((a, b) => a.title.localeCompare(b.title, 'ar'));
  }, [courses, search, category]);

  const dirty = Boolean(search.trim() || category !== 'all');
  const clearFilters = () => {
    setSearch('');
    setCategory('all');
  };
  const isBusy = upsertCourse.isPending || enrollEmployee.isPending || transitionEnrollment.isPending;

  const handleEnrollmentStatus = async (enrollment: LearningEnrollment, status: string) => {
    if (status === enrollment.status) return;
    try {
      await transitionEnrollment.mutateAsync({ enrollmentId: enrollment.id, status });
      const label = ENROLLMENT_LABELS[status as LearningEnrollment['status']] ?? status;
      toast({ message: `تم تحديث الحالة إلى ${label}`, tone: 'success' });
    } catch {
      /* error surfaced via MutationCache global toast */
    }
  };

  const courseColumns: DataTableColumn<LearningCourse>[] = [
    { key: 'code', header: 'الرمز', sortable: true },
    {
      key: 'title',
      header: 'العنوان',
      sortable: true,
      render: (c) => <span className="font-bold">{c.title}</span>,
    },
    { key: 'category', header: 'الفئة', render: (c) => CATEGORY_LABELS[c.category] ?? c.category },
    { key: 'durationMinutes', header: 'المدة', render: (c) => `${c.durationMinutes} دقيقة` },
    {
      key: 'mandatory',
      header: 'النوع',
      render: (c) => <StatusBadge status={c.mandatory ? 'high' : 'normal'} label={c.mandatory ? 'إجباري' : 'اختياري'} />,
    },
    { key: 'enrollments', header: 'التسجيل', sortable: true },
    { key: 'active', header: 'الحالة', render: (c) => <StatusBadge status={c.active ? 'active' : 'inactive'} /> },
    {
      key: 'actions',
      header: 'إجراءات',
      render: (c) => (
        <div className="flex items-center gap-2">
          <button
            type="button"
            title="تسجيل موظف"
            aria-label={`تسجيل موظف في دورة ${c.title}`}
            className="inline-grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:border-[var(--border-strong)] hover:bg-[var(--surface-muted)] hover:text-[var(--text-primary)]"
            onClick={() => setEnrollTarget(c)}
          >
            <UserPlus className="size-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            title="تعديل الدورة"
            aria-label={`تعديل دورة ${c.title}`}
            className="inline-grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:border-[var(--border-strong)] hover:bg-[var(--surface-muted)] hover:text-[var(--text-primary)]"
            onClick={() => setCourseDialog({ course: c })}
          >
            <Pencil className="size-4" aria-hidden="true" />
          </button>
        </div>
      ),
    },
  ];

  const enrollmentColumns: DataTableColumn<LearningEnrollment>[] = [
    {
      key: 'employeeName',
      header: 'الموظف',
      sortable: true,
      render: (e) => <span className="font-bold">{e.employeeName ?? e.employeeCode ?? '—'}</span>,
    },
    { key: 'courseTitle', header: 'الدورة', sortable: true },
    {
      key: 'status',
      header: 'الحالة',
      render: (e) => <StatusBadge status={ENROLLMENT_TONE[e.status]} label={ENROLLMENT_LABELS[e.status]} />,
    },
    { key: 'progress', header: 'التقدم', render: (e) => (e.progress == null ? '—' : `${e.progress}%`) },
    { key: 'score', header: 'النتيجة', render: (e) => (e.score == null ? '—' : String(e.score)) },
    { key: 'enrolledAt', header: 'تاريخ التسجيل', render: (e) => dateFormatter.format(new Date(e.enrolledAt)) },
    {
      key: 'actions',
      header: 'تحديث الحالة',
      render: (e) => (
        <select
          className="rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2 py-1.5 text-xs font-bold text-[var(--text-primary)] transition focus:border-[var(--brand-accent)] focus:outline-none disabled:opacity-50"
          value={e.status}
          disabled={isBusy}
          onChange={(ev) => void handleEnrollmentStatus(e, ev.target.value)}
          aria-label="تحديث حالة التسجيل"
        >
          {Object.entries(ENROLLMENT_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="التدريب والمهارات"
        title="المعهد المهني والتدريب"
        description="إدارة الدورات التدريبية، وتسجيل الموظفين، ومتابعة تقدم التعلم ونتائجه."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary" onClick={() => void catalog.refetch()} disabled={catalog.isFetching}>
              <RefreshCw className={`size-4 ${catalog.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
              تحديث
            </button>
            <button type="button" className="btn-primary" onClick={() => setCourseDialog({ course: null })}>
              <Plus className="size-4" aria-hidden="true" />
              دورة جديدة
            </button>
          </div>
        }
      />

      {catalog.isLoading ? (
        <MetricSkeletonRow count={4} />
      ) : (
        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard label="الدورات النشطة" value={activeCourses} icon={BookOpen} hint="دورات مفعّلة للموظفين" />
          <MetricCard label="إجمالي التسجيل" value={totalEnrollments} icon={GraduationCap} hint="عبر كل الدورات" />
          <MetricCard label="دورات إجبارية" value={mandatoryCount} icon={Award} hint="ضمن خطة التدريب" />
          <MetricCard label="تسجيلات مكتملة" value={completedEnrollments} icon={CheckCircle2} hint="من سجلات الموظفين" />
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث باسم الدورة أو الرمز…"
        resultText={`عرض ${filtered.length} من ${courses.length} دورة`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={category} onChange={(ev) => setCategory(ev.target.value)} aria-label="تصفية حسب الفئة">
          {CATEGORY_ORDER.map((key) => (
            <option key={key} value={key}>
              {key === 'all' ? 'كل الفئات' : (CATEGORY_LABELS[key] ?? key)}
            </option>
          ))}
        </select>
      </FilterBar>

      {catalog.isError ? (
        <ErrorState description={safeErrorMessage(catalog.error)} onRetry={() => void catalog.refetch()} />
      ) : catalog.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل الدورات…" />
      ) : courses.length === 0 ? (
        <EmptyState
          title="لا توجد دورات بعد"
          description="ابدأ بإنشاء أول دورة تدريبية في المعهد المهني، ثم سجّل الموظفين لمتابعة تقدمهم."
          action={
            <button type="button" className="btn-primary" onClick={() => setCourseDialog({ course: null })}>
              <Plus className="size-4" aria-hidden="true" />
              إنشاء دورة
            </button>
          }
        />
      ) : (
        <DataTable<LearningCourse>
          ariaLabel="جدول الدورات التدريبية"
          rowKey={(c) => c.id}
          data={filtered}
          minWidth="960px"
          columns={courseColumns}
          emptyTitle="لا توجد نتائج مطابقة"
          emptyDescription="جرّب تعديل البحث أو تغيير الفئة."
        />
      )}

      <section className="space-y-4">
        <h2 className="text-lg font-black">تسجيلات الموظفين</h2>
        {enrollments.length === 0 ? (
          <EmptyState title="لا توجد تسجيلات" description="سجّل الموظفين في الدورات عبر زر «تسجيل موظف» في جدول الدورات لعرض تقدمهم ونتائجهم هنا." />
        ) : (
          <DataTable<LearningEnrollment>
            ariaLabel="جدول تسجيلات الموظفين"
            rowKey={(e) => e.id}
            data={enrollments}
            minWidth="920px"
            columns={enrollmentColumns}
          />
        )}
      </section>

      {courseDialog ? <CourseFormDialog course={courseDialog.course} onClose={() => setCourseDialog(null)} /> : null}

      {enrollTarget ? <EnrollDialog course={enrollTarget} employees={employees} onClose={() => setEnrollTarget(null)} /> : null}
    </div>
  );
}

function CourseFormDialog({ course, onClose }: { course: LearningCourse | null; onClose: () => void }) {
  const upsertCourse = useUpsertCourse();
  const { toast } = useToast();

  const isEdit = Boolean(course);

  const [code, setCode] = useState(course?.code ?? '');
  const [titleAr, setTitleAr] = useState(course?.title ?? '');
  const [titleEn, setTitleEn] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState(course?.category ?? 'general');
  const [deliveryMode, setDeliveryMode] = useState<string>(course?.deliveryMode ?? 'online');
  const [duration, setDuration] = useState(course ? String(course.durationMinutes) : '60');
  const [passingScore, setPassingScore] = useState('');
  const [validityMonths, setValidityMonths] = useState('');
  const [mandatory, setMandatory] = useState(course?.mandatory ?? false);
  const [active, setActive] = useState(course?.active ?? true);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);

    const codeTrim = code.trim();
    const titleTrim = titleAr.trim();
    if (!codeTrim || !titleTrim) {
      setError('الرمز والعنوان العربي مطلوبان.');
      return;
    }

    const durationValue = Number(duration);
    if (!Number.isFinite(durationValue) || durationValue <= 0) {
      setError('المدة يجب أن تكون رقماً موجباً.');
      return;
    }

    const input: CourseFormInput = {
      id: course?.id ?? null,
      code: codeTrim,
      title_ar: titleTrim,
      title_en: titleEn.trim() || undefined,
      description: description.trim() || undefined,
      category,
      delivery_mode: deliveryMode,
      duration_minutes: Math.round(durationValue),
      mandatory,
      passing_score: passingScore.trim() === '' ? null : Number(passingScore),
      validity_months: validityMonths.trim() === '' ? null : Number(validityMonths),
      active,
    };

    try {
      await upsertCourse.mutateAsync(input);
      toast({ message: isEdit ? 'تم تعديل الدورة بنجاح' : 'تم إنشاء الدورة بنجاح', tone: 'success' });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title={isEdit ? 'تعديل الدورة' : 'إنشاء دورة جديدة'} onClose={onClose} maxWidth="max-w-2xl">
      <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
        {error ? <ErrorBanner message={error} /> : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">الرمز</span>
            <input className="input" value={code} onChange={(e) => setCode(e.target.value)} placeholder="TRN-001" required />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">العنوان (عربي)</span>
            <input className="input" value={titleAr} onChange={(e) => setTitleAr(e.target.value)} placeholder="مهارات التواصل الفعّال" required />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">العنوان (إنجليزي — اختياري)</span>
            <input className="input" value={titleEn} onChange={(e) => setTitleEn(e.target.value)} dir="ltr" placeholder="Effective Communication Skills" />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">الفئة</span>
            <select className="input" value={category} onChange={(e) => setCategory(e.target.value)}>
              {CATEGORY_ORDER.filter((key) => key !== 'all').map((key) => (
                <option key={key} value={key}>
                  {CATEGORY_LABELS[key] ?? key}
                </option>
              ))}
            </select>
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">طريقة التقديم</span>
            <select className="input" value={deliveryMode} onChange={(e) => setDeliveryMode(e.target.value)}>
              {Object.entries(DELIVERY_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">المدة (بالدقائق)</span>
            <input className="input" type="number" min="1" value={duration} onChange={(e) => setDuration(e.target.value)} required />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">درجة النجاح (اختياري)</span>
            <input className="input" type="number" min="0" max="100" value={passingScore} onChange={(e) => setPassingScore(e.target.value)} />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-bold">صلاحية الشهادة بالأشهر (اختياري)</span>
            <input className="input" type="number" min="0" value={validityMonths} onChange={(e) => setValidityMonths(e.target.value)} />
          </label>
        </div>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">الوصف (اختياري)</span>
          <textarea className="input min-h-24 resize-y" value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>

        <div className="flex flex-wrap gap-6">
          <label className="flex items-center gap-2 text-sm font-bold">
            <input type="checkbox" className="size-4 accent-[var(--brand-primary)]" checked={mandatory} onChange={(e) => setMandatory(e.target.checked)} />
            دورة إجبارية
          </label>
          <label className="flex items-center gap-2 text-sm font-bold">
            <input type="checkbox" className="size-4 accent-[var(--brand-primary)]" checked={active} onChange={(e) => setActive(e.target.checked)} />
            مفعّلة
          </label>
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={upsertCourse.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={upsertCourse.isPending}>
            {upsertCourse.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
            {isEdit ? 'حفظ التعديلات' : 'إنشاء الدورة'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

function EnrollDialog({ course, employees, onClose }: { course: LearningCourse; employees: LearningEmployee[]; onClose: () => void }) {
  const enrollEmployee = useEnrollEmployee();
  const { toast } = useToast();

  const [employeeId, setEmployeeId] = useState('');
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);

    if (!employeeId) {
      setError('اختر موظفاً للتسجيل.');
      return;
    }

    try {
      await enrollEmployee.mutateAsync({ employeeId, courseId: course.id });
      toast({ message: `تم تسجيل الموظف في دورة «${course.title}»`, tone: 'success' });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="تسجيل موظف في دورة" onClose={onClose} maxWidth="max-w-lg">
      <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
        {error ? <ErrorBanner message={error} /> : null}

        <p className="text-sm leading-7 text-[var(--text-muted)]">
          سيتم تسجيل الموظف في دورة <span className="font-black text-[var(--text-primary)]">{course.title}</span>.
        </p>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">الموظف</span>
          {employees.length === 0 ? (
            <p className="text-sm text-[var(--text-muted)]">لا يوجد موظفون متاحون للتسجيل.</p>
          ) : (
            <select className="input" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} autoFocus>
              <option value="">— اختر موظفاً —</option>
              {employees.map((employee) => (
                <option key={employee.id} value={employee.id}>
                  {employee.name}
                  {employee.code ? ` (${employee.code})` : ''}
                </option>
              ))}
            </select>
          )}
        </label>

        <div className="flex justify-end gap-3 pt-2">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={enrollEmployee.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={enrollEmployee.isPending || !employeeId}>
            {enrollEmployee.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
            تسجيل
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
