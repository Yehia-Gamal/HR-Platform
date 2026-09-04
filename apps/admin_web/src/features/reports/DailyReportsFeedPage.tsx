import { cairoTodayIso } from '../../core/cairoTime';
import { Heart, MessageCircle, Send, Trash2, ChevronDown, ChevronUp, Plus, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { ListSkeleton } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { useToast } from '../../ui/Toast';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAuth } from '../auth/AuthProvider';
import {
  useAddDailyReportComment,
  useDailyReportsFeed,
  useDeleteDailyReportComment,
  useSubmitDailyReport,
  useToggleDailyReportLike,
} from './useDailyReportsFeed';

import { DailyReportsSummarizerCard } from './DailyReportsSummarizerCard';

export function DailyReportsFeedPage() {
  const { toast } = useToast();
  const auth = useAuth();
  const query = useDailyReportsFeed();
  const toggleLike = useToggleDailyReportLike();
  const addComment = useAddDailyReportComment();
  const deleteComment = useDeleteDailyReportComment();
  const submitReport = useSubmitDailyReport();
  const [commentDrafts, setCommentDrafts] = useState<Record<string, string>>({});
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [showComposer, setShowComposer] = useState(false);
  const [draft, setDraft] = useState({ achievements: '', blockers: '', tomorrowPlan: '' });

  const items = useMemo(() => query.data ?? [], [query.data]);

  const submitComment = (reportId: string, text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    addComment.mutate(
      { reportId, comment: trimmed },
      {
        onSuccess: () => {
          setCommentDrafts((prev) => ({ ...prev, [reportId]: '' }));
          toast({ message: 'تم إضافة التعليق بنجاح', tone: 'success' });
        },
        onError: (err) => toast({ message: safeErrorMessage(err), tone: 'error' }),
      },
    );
  };

  const handleToggleLike = (reportId: string) => {
    toggleLike.mutate(reportId, {
      onError: (err) => toast({ message: safeErrorMessage(err), tone: 'error' }),
    });
  };

  const handleDeleteComment = (commentId: string) => {
    deleteComment.mutate(commentId, {
      onSuccess: () => toast({ message: 'تم حذف التعليق', tone: 'success' }),
      onError: (err) => toast({ message: safeErrorMessage(err), tone: 'error' }),
    });
  };

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <PageHeader title="التقارير اليومية" description="سجل مفتوح لكل الموظفين: الإنجازات والمعوقات وخطة الغد — تفاعل بالإعجاب والتعليق." />

      {/* بطاقة الملخص التنفيذي الذكي */}
      <DailyReportsSummarizerCard reports={items} />

      {/* زر تقرير جديد + النموذج */}
      <div className="flex justify-end">
        <button className="btn-primary inline-flex items-center gap-2" onClick={() => setShowComposer(true)}>
          <Plus className="size-4" aria-hidden="true" /> تقرير جديد
        </button>
      </div>

      {showComposer ? (
        <div className="card space-y-4 p-5">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-black">تقرير اليوم</h3>
            <button className="rounded-full p-1 text-[var(--text-muted)] hover:bg-[var(--surface-muted)]" onClick={() => setShowComposer(false)}>
              <X className="size-5" aria-hidden="true" />
            </button>
          </div>
          <label className="block">
            <span className="mb-1.5 block text-sm font-semibold">
              الإنجازات <span className="text-[var(--danger)]">*</span>
            </span>
            <textarea
              className="input min-h-20 w-full"
              placeholder="ما الذي أنجزته اليوم؟"
              value={draft.achievements}
              onChange={(e) => setDraft((p) => ({ ...p, achievements: e.target.value }))}
            />
          </label>
          <label className="block">
            <span className="mb-1.5 block text-sm font-semibold">المعوقات</span>
            <textarea
              className="input min-h-16 w-full"
              placeholder="هل واجهت عقبات؟"
              value={draft.blockers}
              onChange={(e) => setDraft((p) => ({ ...p, blockers: e.target.value }))}
            />
          </label>
          <label className="block">
            <span className="mb-1.5 block text-sm font-semibold">خطة الغد</span>
            <textarea
              className="input min-h-16 w-full"
              placeholder="ما الذي تخطط لإنجازه غداً؟"
              value={draft.tomorrowPlan}
              onChange={(e) => setDraft((p) => ({ ...p, tomorrowPlan: e.target.value }))}
            />
          </label>
          {submitReport.isError ? <p className="text-sm text-[var(--danger)]">{safeErrorMessage(submitReport.error)}</p> : null}
          <div className="flex justify-end gap-2">
            <button className="btn-secondary" onClick={() => setShowComposer(false)}>
              إلغاء
            </button>
            <button
              className="btn-primary inline-flex items-center gap-2"
              disabled={submitReport.isPending || draft.achievements.trim().length < 3}
              onClick={() => {
                submitReport.mutate(
                  {
                    reportDate: cairoTodayIso(),
                    achievements: draft.achievements.trim(),
                    blockers: draft.blockers.trim() || undefined,
                    tomorrowPlan: draft.tomorrowPlan.trim() || undefined,
                  },
                  {
                    onSuccess: () => {
                      toast({ message: 'تم نشر تقريرك بنجاح', tone: 'success' });
                      setShowComposer(false);
                      setDraft({ achievements: '', blockers: '', tomorrowPlan: '' });
                    },
                    onError: (err) => toast({ message: safeErrorMessage(err), tone: 'error' }),
                  },
                );
              }}
            >
              {submitReport.isPending ? 'جارٍ النشر…' : 'نشر التقرير'}
            </button>
          </div>
        </div>
      ) : null}

      {query.isError ? (
        <ErrorState title="تعذر تحميل التقارير" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && items.length === 0 ? (
        <ListSkeleton rows={4} label="جارٍ تحميل التقارير" />
      ) : items.length === 0 ? (
        <EmptyState title="لا توجد تقارير بعد" description="عندما يرفع الموظفون تقاريرهم اليومية ستظهر هنا." />
      ) : (
        <>
          {items.map((item) => {
            const isExpanded = expanded[item.id];
            return (
              <article
                key={item.id}
                className="report-card overflow-hidden rounded-[18px] border border-[var(--border)] bg-[var(--surface)] transition-[box-shadow,transform] duration-200"
              >
                {/* ─── رأس البطاقة: الصورة + الاسم + المسمى + المدير + التاريخ ─── */}
                <div className="flex items-center gap-3 border-b border-[var(--border)] p-4">
                  <UserAvatar displayName={item.employeeName} photoUrl={item.photoUrl} size="lg" announceName={false} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-base font-black">{item.employeeName}</p>
                    <div className="flex flex-wrap gap-1.5">
                      {item.jobTitle ? <span className={chipClass('primary')}>{item.jobTitle}</span> : null}
                      {item.department ? <span className={chipClass('neutral')}>{item.department}</span> : null}
                    </div>
                  </div>
                  <div className="shrink-0 text-left">
                    <p className="text-xs font-bold text-[var(--text-muted)]">
                      {new Intl.DateTimeFormat('ar-EG', {
                        day: 'numeric',
                        month: 'long',
                        year: 'numeric',
                      }).format(new Date(`${item.reportDate}T00:00:00`))}
                    </p>
                    <p className="text-[10px] text-[var(--text-muted)]">
                      {new Intl.DateTimeFormat('ar-EG', { weekday: 'long' }).format(new Date(`${item.reportDate}T00:00:00`))}
                    </p>
                  </div>
                </div>

                {/* ─── المحتوى: الإنجازات / المعوقات / خطة الغد (بارتفاع محدود + تمرير) ─── */}
                <div className={`report-content ${isExpanded ? '' : 'max-h-[200px] overflow-y-auto'} p-5 text-sm leading-[1.8]`}>
                  <div className="mb-3">
                    <span className="inline-block rounded-full bg-[var(--brand-primary-soft)] px-2 py-0.5 text-xs font-black text-[var(--brand-primary)]">
                      ✓ الإنجازات
                    </span>
                    <p className="mt-1.5 whitespace-pre-wrap">{item.achievements}</p>
                  </div>
                  {item.blockers ? (
                    <div className="mb-3">
                      <span className="inline-block rounded-full bg-[var(--warning-soft)] px-2 py-0.5 text-xs font-black text-[var(--warning)]">
                        ⚠ المعوقات
                      </span>
                      <p className="mt-1.5 whitespace-pre-wrap">{item.blockers}</p>
                    </div>
                  ) : null}
                  {item.tomorrowPlan ? (
                    <div className="mb-1">
                      <span className="inline-block rounded-full bg-[var(--success-soft)] px-2 py-0.5 text-xs font-black text-[var(--success)]">
                        → خطة الغد
                      </span>
                      <p className="mt-1.5 whitespace-pre-wrap">{item.tomorrowPlan}</p>
                    </div>
                  ) : null}
                </div>

                {/* زر توسيع/طي */}
                <button
                  className="flex w-full items-center justify-center gap-1 py-2 text-xs font-bold text-[var(--text-muted)] transition hover:bg-[var(--surface-muted)]"
                  onClick={() => setExpanded((prev) => ({ ...prev, [item.id]: !prev[item.id] }))}
                >
                  {isExpanded ? (
                    <>
                      <ChevronUp className="size-3.5" /> طي
                    </>
                  ) : (
                    <>
                      <ChevronDown className="size-3.5" /> عرض الكل
                    </>
                  )}
                </button>

                {/* ─── تعليق المدير (إن وجد) ─── */}
                {item.managerComment ? (
                  <div className="mx-4 mb-3 rounded-2xl bg-[var(--surface-muted)] p-3">
                    <p className="text-xs font-black text-[var(--text-muted)]">تعليق المدير{item.reviewedByName ? ` — ${item.reviewedByName}` : ''}</p>
                    <p className="mt-1 text-sm leading-7">{item.managerComment}</p>
                  </div>
                ) : null}

                {/* ─── شريط التفاعل: إعجاب + تعليقات ─── */}
                <div className="flex items-center gap-2 border-t border-[var(--border)] px-4 py-3">
                  <button
                    className={`flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-bold transition active:scale-95 ${
                      item.isLikedByMe ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-muted)]'
                    }`}
                    disabled={toggleLike.isPending}
                    onClick={() => handleToggleLike(item.id)}
                  >
                    <Heart className="size-4" style={item.isLikedByMe ? { fill: 'currentColor' } : {}} aria-hidden="true" />
                    {item.likesCount > 0 ? item.likesCount : 'إعجاب'}
                  </button>
                  <button
                    className="flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-bold transition hover:bg-[var(--surface-muted)] active:scale-95"
                    onClick={() =>
                      setExpanded((prev) => ({
                        ...prev,
                        [item.id]: !prev[item.id],
                      }))
                    }
                  >
                    <MessageCircle className="size-4" aria-hidden="true" />
                    {item.comments.length > 0 ? item.comments.length : 'تعليق'}
                  </button>
                </div>

                {/* ─── قسم التعليقات ─── */}
                {isExpanded ? (
                  <div className="space-y-2 px-4 pb-4">
                    {item.comments.map((comment) => (
                      <div key={comment.id} className="flex items-start justify-between gap-2 rounded-2xl bg-[var(--surface-muted)] p-3">
                        <div className="min-w-0 flex-1">
                          <p className="text-sm font-black">{comment.employeeName}</p>
                          <p className="mt-0.5 text-sm leading-7">{comment.comment}</p>
                          <p className="mt-1 text-[10px] text-[var(--text-muted)]">
                            {new Intl.DateTimeFormat('ar-EG', {
                              hour: '2-digit',
                              minute: '2-digit',
                              day: 'numeric',
                              month: 'short',
                            }).format(new Date(comment.createdAt))}
                          </p>
                        </div>
                        {comment.employeeId === auth.access?.employeeId ? (
                          <button
                            className="shrink-0 rounded-full p-1.5 text-[var(--danger)] transition hover:bg-[var(--danger-soft)]"
                            aria-label="حذف"
                            disabled={deleteComment.isPending}
                            onClick={() => handleDeleteComment(comment.id)}
                          >
                            <Trash2 className="size-4" aria-hidden="true" />
                          </button>
                        ) : null}
                      </div>
                    ))}
                    {item.comments.length === 0 ? (
                      <p className="py-2 text-center text-sm text-[var(--text-muted)]">لا توجد تعليقات بعد — كن أول من يعلّق</p>
                    ) : null}

                    {/* صندوق كتابة تعليق */}
                    <div className="flex items-center gap-2 pt-1">
                      <input
                        className="input flex-1 rounded-full"
                        placeholder="اكتب تعليقًا…"
                        value={commentDrafts[item.id] ?? ''}
                        onChange={(e) => setCommentDrafts((prev) => ({ ...prev, [item.id]: e.target.value }))}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' && !e.shiftKey) {
                            e.preventDefault();
                            submitComment(item.id, commentDrafts[item.id] ?? '');
                          }
                        }}
                      />
                      <button
                        className="flex size-10 items-center justify-center rounded-full bg-[var(--brand-primary)] text-white transition active:scale-90"
                        disabled={addComment.isPending || !(commentDrafts[item.id] ?? '').trim()}
                        onClick={() => submitComment(item.id, commentDrafts[item.id] ?? '')}
                      >
                        <Send className="size-4" aria-hidden="true" />
                      </button>
                    </div>
                  </div>
                ) : null}
              </article>
            );
          })}

          {/* تنبيه: لعرض المزيد حمّل الصفحة مرة أخرى */}
        </>
      )}

      <style>{`
        .report-card:hover {
          box-shadow: 0 4px 20px rgba(0,0,0,.08);
          transform: translateY(-1px);
        }
        .report-content::-webkit-scrollbar {
          width: 6px;
        }
        .report-content::-webkit-scrollbar-thumb {
          background: var(--border);
          border-radius: 3px;
        }
        @media (max-width: 640px) {
          .report-content {
            font-size: 13px !important;
          }
        }
      `}</style>
    </div>
  );
}

/** أنماط الفقاعات (chips) */
function chipClass(variant: 'primary' | 'neutral' | 'muted'): string {
  const base = 'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-extrabold';
  switch (variant) {
    case 'primary':
      return `${base} bg-[var(--brand-primary-soft)] text-[var(--brand-primary)]`;
    case 'neutral':
      return `${base} bg-[var(--surface-muted)] text-[var(--text)]`;
    case 'muted':
      return `${base} border border-[var(--border)] bg-transparent font-bold text-[var(--text-muted)]`;
  }
}
