import {
  AlertTriangle,
  Award,
  Bot,
  Building2,
  Calculator,
  Calendar,
  CheckCircle2,
  ChevronRight,
  ClipboardList,
  Copy,
  FileBadge,
  FileSignature,
  FileText,
  HelpCircle,
  MailCheck,
  Maximize2,
  Minimize2,
  Printer,
  RefreshCw,
  Send,
  ShieldAlert,
  Sparkles,
  User,
  X,
} from 'lucide-react';
import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { useToast } from '../../ui/Toast';

interface ChatMessage {
  id: string;
  sender: 'user' | 'assistant';
  text: string;
  timestamp: string;
  quickAction?: string;
}

type CopilotMode = 'chat' | 'letters' | 'calculator';

const PRESET_FAQS: { q: string; a: string; category: string }[] = [
  {
    category: 'إجازات',
    q: 'كم يبلغ رصيد الإجازات السنوية المستحقة قانوناً؟',
    a: 'وفقاً لقانون العمل واللائحة الداخلية:\n• 21 يوماً سنوياً لمن أمضى سنة كاملة في الخدمة.\n• 30 يوماً لمن أمضى 10 سنوات أو تجاوز سن الخمسين.\n• يحق للموظف إجازة عارضة 6 أيام بحد أقصى يومين في المرة الواحدة تخصم من رصيده.',
  },
  {
    category: 'حضور وانصراف',
    q: 'ما هو التدرج القانوني لجزاءات التأخير بدون إذن؟',
    a: 'التدرج المعتمد للائحة الجزاءات خلال الشهر الواحد:\n1. التأخير الأول حتى 15 دقيقة: إنذار كتابي أو خصم ربع يوم.\n2. التأخير الثاني حتى 30 دقيقة: خصم نصف يوم.\n3. التأخير الثالث حتى 60 دقيقة: خصم يوم كامل.\n4. التأخير الرابع فما بعد: خصم يومين مع الإحالة للتحقيق الداخلي.',
  },
  {
    category: 'بدلات ومأموريات',
    q: 'ما هي ضوابط اعتماد وتصريح المأموريات والقوافل الميدانية؟',
    a: 'تتطلب المأمورية الخارجية:\n• تقديم طلب مسبق عبر المنظومة بموقع وتوقيت المأمورية.\n• اعتماد مباشر من المدير المباشر ومدير الفرع.\n• تسجيل بصمة الموقع GPS في نطاق نقطة التمركز المعتمدة، مع صرف بدل الانتقال الميداني المعتمد.',
  },
  {
    category: 'ساعات العمل',
    q: 'كيف يتم احتساب ساعات العمل الإضافي (Overtime)؟',
    a: 'يُحسب أجر ساعة العمل الإضافي بواقع:\n• الأجر الأساسي للساعة + 35% عن ساعات العمل النهارية.\n• الأجر الأساسي للساعة + 70% عن ساعات العمل الليلية.\n• الأجر مضاعفاً 100% في أيام العطلات الأسبوعية والرسمية أو منح راحة بديلة.',
  },
];

export function HRCopilotDrawer({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const auth = useAuth();
  const { toast } = useToast();
  const [mode, setMode] = useState<CopilotMode>('chat');

  // Chat State
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 'm1',
      sender: 'assistant',
      text: `مرحباً ${auth.access?.displayName ?? 'بك'}! 👋\nأنا المساعد الإداري الذكي (HR Copilot).\nكيف يمكنني مساعدتك اليوم في لوائح الموارد البشرية، صياغة الخطابات، أو احتساب الجزاءات؟`,
      timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
    },
  ]);
  const [inputValue, setInputValue] = useState('');
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  // Letter Generator State
  const [letterType, setLetterType] = useState<'warning' | 'appreciation' | 'experience' | 'mission'>('warning');
  const [empName, setEmpName] = useState('');
  const [empRole, setEmpRole] = useState('');
  const [letterReason, setLetterReason] = useState('');
  const [generatedLetter, setGeneratedLetter] = useState('');

  // Calculator State
  const [calcSalary, setCalcSalary] = useState(6000);
  const [penaltyType, setPenaltyType] = useState<'late_1' | 'late_2' | 'late_3' | 'absence_1' | 'absence_2' | 'no_checkout'>('late_1');

  // Auto-scroll chat
  useEffect(() => {
    if (mode === 'chat') {
      messagesEndRef.current?.scrollIntoView?.({ behavior: 'smooth' });
    }
  }, [messages, mode]);

  // Keyboard shortcut Esc to close
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  const handleSendMessage = (textToSend?: string) => {
    const text = (textToSend ?? inputValue).trim();
    if (!text) return;

    const userMsg: ChatMessage = {
      id: `u-${Date.now()}`,
      sender: 'user',
      text,
      timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
    };

    setMessages((prev) => [...prev, userMsg]);
    if (!textToSend) setInputValue('');

    // الرد الذكي اللحظي بناءً على سياق السؤال
    setTimeout(() => {
      let reply = '';
      const lower = text.toLowerCase();

      if (lower.includes('إجاز') || lower.includes('اجاز') || lower.includes('سنوي') || lower.includes('عارض')) {
        reply =
          '📋 **ضوابط الإجازات وفق اللائحة:**\n' +
          '• الإجازة الاعتيادية: 21 يوماً سنوياً تزداد إلى 30 يوماً بعد 10 سنوات خدمة.\n' +
          '• الإجازة العارضة: حدها الأقصى 6 أيام بالعام لظروف طارئة (يومان كحد أقصى لكل طلب).\n' +
          '• يجب تقديم طلب الإجازة مسبقاً عبر المنظومة لضمان تغطية وردية العمل دون عجز.';
      } else if (lower.includes('تأخير') || lower.includes('تأخر') || lower.includes('خصم') || lower.includes('جزاء')) {
        reply =
          '⚖️ **لائحة الجزاءات المعتمدة للتأخير:**\n' +
          '• المرة الأولى: إنذار شفوي / لفت نظر.\n' +
          '• المرة الثانية: خصم ربع يوم من الراتب الأساسي.\n' +
          '• المرة الثالثة: خصم نصف يوم.\n' +
          '• المرة الرابعة: خصم يوم كامل.\n' +
          '💡 يمكنك التبديل لتبويب «محاكي الخصومات» أعلاه لحساب المبلغ بالجنيه فورياً!';
      } else if (lower.includes('مأمور') || lower.includes('قافل') || lower.includes('ميدان')) {
        reply =
          '🚗 **المأموريات والقوافل الميدانية:**\n' +
          '• تسجل المأمورية عبر قسم الحضور والمأموريات مع تحديد نقطة الانطلاق والوجهة.\n' +
          '• تتطلب اعتماد المدير المباشر.\n' +
          '• يُحسب للموظف بدل انتقال ومصروفات معتمدة حسب بُعد المسافة وطبيعة التكليف.';
      } else if (lower.includes('عقد') || lower.includes('استقال') || lower.includes('إخلاء') || lower.includes('شهادة')) {
        reply =
          '📄 **إجراءات إنهاء الخدمة وشهادات الخبرة:**\n' +
          '• تمنح المؤسسة شهادة خبرة رسمية توضح مدة الخدمة والمسمى الوظيفي دون مصاريف.\n' +
          '• تتطلب إتمام محضر تسليم العهد وإخلاء الطرف من الشؤون الإدارية والمالية.\n' +
          '💡 يمكنك توليد مسودة شهادة خبرة جاهزة للطباعة من تبويب «صانع الخطابات».';
      } else {
        reply =
          `تم استلام استفسارك بخصوص "${text}".\n` +
          'تلتزم المنظومة بتطبيق لوائح العمل المعتمدة للحفاظ على حقوق الموظف واستقرار العمل.\n' +
          'يمكنك استخدام الاختصارات السريعة بالأسفل أو التبديل لـ «صانع الخطابات» و «محاكي الخصومات» لإتمام الإجراء المطلوب بنقرة واحدة.';
      }

      const botMsg: ChatMessage = {
        id: `b-${Date.now()}`,
        sender: 'assistant',
        text: reply,
        timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
      };
      setMessages((prev) => [...prev, botMsg]);
    }, 450);
  };

  const handleGenerateLetter = (e: React.FormEvent) => {
    e.preventDefault();
    const dateStr = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date());
    const name = empName.trim() || 'الموظف المحترم';
    const role = empRole.trim() || 'الموظف بالشركة';
    const reason = letterReason.trim();

    let content = '';

    if (letterType === 'warning') {
      content =
        `بسم الله الرحمن الرحيم\n` +
        `التاريخ: ${dateStr}\n\n` +
        `الموضوع: لفت نظر / إنذار إداري بخصوص الانضباط الوظيفي\n\n` +
        `إلى السيد الزميل: ${name}\n` +
        `الوظيفة: ${role}\n\n` +
        `تحية طيبة وبعد،،\n\n` +
        `نظراً لما لوحظ من ${reason || 'تكرار التأخير عن مواعيد العمل الرسمية دون إذن مسبق'}، ومخالفة لوائح العمل الداخلية المنظمة لمواعيد الحضور والانصراف،\n\n` +
        `فإن إدارة الموارد البشرية توجه لسيادتكم هذا الخطاب كلفت نظر وإنذار، آملين تدارك ذلك والالتزام الدقيق بمواعيد العمل المقررة حفاظاً على حسن سير المنظومة والإنتاجية.\n\n` +
        `وتفضلوا بقبول فائق الاحترام والتقدير،،\n\n` +
        `إدارة الموارد البشرية والعمليات\n` +
        `مؤسسة أحلى شباب`;
    } else if (letterType === 'appreciation') {
      content =
        `بسم الله الرحمن الرحيم\n` +
        `التاريخ: ${dateStr}\n\n` +
        `الموضوع: شهادة شكر وتقدير وتميز إداري\n\n` +
        `إلى الزميل العزيز: ${name}\n` +
        `الوظيفة: ${role}\n\n` +
        `السلام عليكم ورحمة الله وبركاته،،\n\n` +
        `يسر إدارة مؤسسة أحلى شباب أن تتقدم لسيادتكم بأسمى آيات الشكر والامتنان، تقديراً لـ ${reason || 'جهودكم المتميزة وتفانيكم الاستثنائي في إنجاز المهام المسندة إليكم بأعلى معايير الدقة والالتزام'}.\n\n` +
        `إن المؤسسة تفخر بكفاءتكم وتتمنى لكم دوام التقدم والازدهار والريادة في مسيرتكم المهنية.\n\n` +
        `وتفضلوا بقبول فائق التقدير والاعتزاز،،\n\n` +
        `المدير التنفيذي وإدارة الموارد البشرية\n` +
        `مؤسسة أحلى شباب`;
    } else if (letterType === 'experience') {
      content =
        `بسم الله الرحمن الرحيم\n` +
        `التاريخ: ${dateStr}\n\n` +
        `الموضوع: شهادة خبرة وإفادة بالخدمة\n\n` +
        `تشهد إدارة مؤسسة أحلى شباب بأن السيد / ${name}\n` +
        `قد عمل طرفنا بوظيفة: ${role}\n` +
        `وقد أدى عمله خلال فترة خدمته بكفاءة وأمانة وتفانٍ، وكان مثالاً يحتذى به في الانضباط وحسن التعاون مع زملائه.\n\n` +
        `وقد سُلمت له هذه الشهادة بناءً على طلبه لتقديمها إلى من يهمه الأمر دون أدنى مسؤولية على المؤسسة تجاه حقوق الغير.\n\n` +
        `مع خالص تمنياتنا له بالتوفيق والنجاح،،\n\n` +
        `مدير إدارة الموارد البشرية\n` +
        `مؤسسة أحلى شباب`;
    } else {
      content =
        `بسم الله الرحمن الرحيم\n` +
        `التاريخ: ${dateStr}\n\n` +
        `الموضوع: قرار تكليف بمأمورية عمل رسمية\n\n` +
        `إلى السيد الزميل: ${name}\n` +
        `الوظيفة: ${role}\n\n` +
        `تقرر تكليفكم رسمياً بأداء مأمورية عمل ميدانية لمتابعة: ${reason || 'أعمال التوزيع والقوافل الميدانية المعتمدة'}.\n\n` +
        `على كافة الإدارات المعنية تقديم التسهيلات اللازمة لإتمام المأمورية وتوفير وسائل الدعم والانتقال المعتمدة.\n\n` +
        `مدير عام العمليات\n` +
        `مؤسسة أحلى شباب`;
    }

    setGeneratedLetter(content);
    toast({ message: 'تم توليد مسودة الخطاب الإداري بنجاح!', tone: 'success' });
  };

  const handleCopyText = (text: string, label = 'النص') => {
    void navigator.clipboard.writeText(text);
    toast({ message: `تم نسخ ${label} إلى الحافظة!`, tone: 'success' });
  };

  // Penalty Calculation logic
  const calcResult = useMemo(() => {
    const dailyRate = Math.round(calcSalary / 30);
    const hourlyRate = Math.round(dailyRate / 8);

    let deductionFactor = 0; // بالأيام
    let ruleText = '';
    let recommendation = '';

    switch (penaltyType) {
      case 'late_1':
        deductionFactor = 0;
        ruleText = 'تأخير للمرة الأولى خلال الشهر (إنذار / لفت نظر دون خصم مالي)';
        recommendation = 'توجيه إنذار شفهي وتذكير الموظف بموعد الوردية';
        break;
      case 'late_2':
        deductionFactor = 0.25;
        ruleText = 'تأخير للمرة الثانية (خصم ربع يوم عمل 25%)';
        recommendation = 'إشعار الموظف بالخصم وتنبيهه من تكرار التأخير';
        break;
      case 'late_3':
        deductionFactor = 0.5;
        ruleText = 'تأخير للمرة الثالثة (خصم نصف يوم عمل 50%)';
        recommendation = 'إنذار كتابي وتأكيد تطبيق خصم اليوم الكامل عند التكرار';
        break;
      case 'absence_1':
        deductionFactor = 1;
        ruleText = 'غياب يوم بدون إذن مسبق (خصم يوم كامل + حرمان من بدل الحضور)';
        recommendation = 'طلب تقديم عذر قهري خلال 48 ساعة أو اعتماد الخصم';
        break;
      case 'absence_2':
        deductionFactor = 2;
        ruleText = 'تكرار الغياب بدون إذن للمرة الثانية (خصم يومين عمل)';
        recommendation = 'إحالة للشؤون القانونية لبحث أسباب الانقطاع';
        break;
      case 'no_checkout':
        deductionFactor = 0.25;
        ruleText = 'عدم تسجيل بصمة الانصراف دون إثبات مأمورية (خصم ساعتين / ربع يوم)';
        recommendation = 'طلب اعتماد إفادة المدير المباشر بتوقيت الانصراف الفعلي';
        break;
    }

    const deductedAmount = Math.round(dailyRate * deductionFactor);

    return {
      dailyRate,
      hourlyRate,
      deductionFactor,
      deductedAmount,
      ruleText,
      recommendation,
    };
  }, [calcSalary, penaltyType]);

  if (!isOpen) return null;

  return (
    <aside
      className="fixed inset-y-0 left-0 z-50 flex w-full max-w-lg flex-col border-r border-[var(--border)] bg-[var(--surface)] shadow-2xl transition-all duration-300 animate-in slide-in-from-left"
      aria-label="المساعد الإداري الذكي HR Copilot"
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-[var(--border)] bg-gradient-to-r from-[var(--surface-muted)] to-[var(--surface)] px-5 py-4">
        <div className="flex items-center gap-3">
          <div className="flex size-10 items-center justify-center rounded-xl bg-[var(--brand-primary)] text-white shadow-xs">
            <Sparkles className="size-5 animate-pulse" aria-hidden="true" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-black text-[var(--text)]">المساعد الإداري الذكي</h3>
              <span className="rounded-full bg-cyan-500/10 px-2 py-0.5 text-[10px] font-black text-cyan-600 dark:text-cyan-400 border border-cyan-500/20">
                Copilot AI
              </span>
            </div>
            <p className="text-xs text-[var(--text-muted)]">لوائح العمل · صياغة الخطابات · حاسبة الجزاءات</p>
          </div>
        </div>

        <button
          type="button"
          onClick={onClose}
          className="icon-button"
          aria-label="إغلاق المساعد الذكي (Esc)"
          title="إغلاق (Esc)"
        >
          <X className="size-5" aria-hidden="true" />
        </button>
      </div>

      {/* Tabs */}
      <div className="flex items-center border-b border-[var(--border)] bg-[var(--surface)] px-4">
        <button
          type="button"
          onClick={() => setMode('chat')}
          className={`flex flex-1 items-center justify-center gap-2 py-3 text-xs font-bold transition-colors border-b-2 ${
            mode === 'chat'
              ? 'border-[var(--brand-primary)] text-[var(--brand-primary)] font-black'
              : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text)]'
          }`}
        >
          <Bot className="size-4" aria-hidden="true" />
          المحادثة واللوائح
        </button>

        <button
          type="button"
          onClick={() => setMode('letters')}
          className={`flex flex-1 items-center justify-center gap-2 py-3 text-xs font-bold transition-colors border-b-2 ${
            mode === 'letters'
              ? 'border-[var(--brand-primary)] text-[var(--brand-primary)] font-black'
              : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text)]'
          }`}
        >
          <FileSignature className="size-4" aria-hidden="true" />
          صانع الخطابات
        </button>

        <button
          type="button"
          onClick={() => setMode('calculator')}
          className={`flex flex-1 items-center justify-center gap-2 py-3 text-xs font-bold transition-colors border-b-2 ${
            mode === 'calculator'
              ? 'border-[var(--brand-primary)] text-[var(--brand-primary)] font-black'
              : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text)]'
          }`}
        >
          <Calculator className="size-4" aria-hidden="true" />
          حاسبة الجزاءات
        </button>
      </div>

      {/* Mode 1: Chat & Knowledge */}
      {mode === 'chat' && (
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* أسئلة سريعة شائعة */}
          <div className="border-b border-[var(--border)] bg-[var(--surface-muted)]/40 p-3">
            <span className="text-[11px] font-bold text-[var(--text-muted)] block mb-1.5">استفسارات شائعة بنقرة واحدة:</span>
            <div className="flex gap-2 overflow-x-auto pb-1 scrollbar-none">
              {PRESET_FAQS.map((faq, idx) => (
                <button
                  key={idx}
                  type="button"
                  onClick={() => handleSendMessage(faq.q)}
                  className="shrink-0 rounded-full border border-[var(--border)] bg-[var(--surface)] px-3 py-1 text-xs font-medium text-[var(--text)] hover:border-[var(--brand-primary)] hover:text-[var(--brand-primary)] transition-all shadow-2xs"
                >
                  {faq.q}
                </button>
              ))}
            </div>
          </div>

          {/* Messages Container */}
          <div className="flex-1 space-y-4 overflow-y-auto p-4">
            {messages.map((m) => (
              <div
                key={m.id}
                className={`flex flex-col ${m.sender === 'user' ? 'items-end' : 'items-start'}`}
              >
                <div
                  className={`max-w-[88%] rounded-2xl p-3.5 text-xs leading-relaxed shadow-2xs ${
                    m.sender === 'user'
                      ? 'bg-[var(--brand-primary)] text-white rounded-br-none'
                      : 'bg-[var(--surface-muted)] border border-[var(--border)] text-[var(--text)] rounded-bl-none'
                  }`}
                >
                  <p className="whitespace-pre-line">{m.text}</p>
                  {m.sender === 'assistant' && (
                    <div className="mt-2 flex items-center justify-end border-t border-[var(--border)]/40 pt-1.5 text-[10px]">
                      <button
                        type="button"
                        onClick={() => handleCopyText(m.text, 'الرد')}
                        className="flex items-center gap-1 text-[var(--text-muted)] hover:text-[var(--brand-primary)] transition-colors"
                        title="نسخ الرد"
                      >
                        <Copy className="size-3" aria-hidden="true" />
                        نسخ
                      </button>
                    </div>
                  )}
                </div>
                <span className="mt-1 px-1 text-[10px] text-[var(--text-muted)]">{m.timestamp}</span>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>

          {/* Chat Input */}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleSendMessage();
            }}
            className="border-t border-[var(--border)] bg-[var(--surface)] p-3"
          >
            <div className="flex items-center gap-2">
              <input
                type="text"
                placeholder="اسأل عن سياسات العمل، الإجازات، التأخيرات..."
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                className="input flex-1 text-xs py-2"
              />
              <button
                type="submit"
                disabled={!inputValue.trim()}
                className="btn-primary size-9 rounded-xl flex items-center justify-center p-0 shrink-0"
                aria-label="إرسال"
              >
                <Send className="size-4" aria-hidden="true" />
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Mode 2: Letter Generator */}
      {mode === 'letters' && (
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          <form onSubmit={handleGenerateLetter} className="card p-4 border border-[var(--border)] space-y-3">
            <h4 className="text-xs font-black text-[var(--text)] flex items-center gap-1.5">
              <FileSignature className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
              بيانات الخطاب الإداري المطلوب
            </h4>

            <div>
              <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">نوع الخطاب الإداري</label>
              <select
                value={letterType}
                onChange={(e) => setLetterType(e.target.value as typeof letterType)}
                className="input w-full text-xs"
              >
                <option value="warning">إنذار رسمي / لفت نظر بشأن الحضور والانضباط</option>
                <option value="appreciation">خطاب شكر وتقدير للإنجاز والتميز</option>
                <option value="experience">شهادة خبرة وإفادة بالخدمة</option>
                <option value="mission">قرار تكليف بمأمورية عمل رسمية</option>
              </select>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">اسم الموظف</label>
                <input
                  type="text"
                  required
                  placeholder="مثال: أحمد محمد علي"
                  value={empName}
                  onChange={(e) => setEmpName(e.target.value)}
                  className="input w-full text-xs"
                />
              </div>
              <div>
                <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">المسمى الوظيفي / الإدارة</label>
                <input
                  type="text"
                  placeholder="مثال: منسق عمليات ميدانية"
                  value={empRole}
                  onChange={(e) => setEmpRole(e.target.value)}
                  className="input w-full text-xs"
                />
              </div>
            </div>

            <div>
              <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">السبب أو التفاصيل الداعمة (اختياري)</label>
              <textarea
                rows={2}
                placeholder="مثال: تكرار التأخير أكثر من 3 مرات / تحقيق مستهدف الـ KPI بنسبة 115%..."
                value={letterReason}
                onChange={(e) => setLetterReason(e.target.value)}
                className="input w-full text-xs"
              />
            </div>

            <button type="submit" className="btn-primary w-full text-xs flex items-center justify-center gap-2 py-2">
              <Sparkles className="size-3.5" aria-hidden="true" />
              توليد الخطاب الإداري
            </button>
          </form>

          {/* Generated Letter Preview */}
          {generatedLetter && (
            <div className="card p-4 border-2 border-[var(--brand-primary)]/40 bg-[var(--surface)] space-y-3 animate-in fade-in">
              <div className="flex items-center justify-between border-b border-[var(--border)] pb-2">
                <span className="text-xs font-black text-[var(--brand-primary)] flex items-center gap-1.5">
                  <CheckCircle2 className="size-4 text-emerald-500" aria-hidden="true" />
                  مسودة الخطاب جاهزة للاعتماد
                </span>
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    onClick={() => handleCopyText(generatedLetter, 'الخطاب')}
                    className="btn-secondary text-[11px] py-1 px-2.5 flex items-center gap-1"
                  >
                    <Copy className="size-3" aria-hidden="true" />
                    نسخ
                  </button>
                  <button
                    type="button"
                    onClick={() => window.print()}
                    className="btn-secondary text-[11px] py-1 px-2.5 flex items-center gap-1"
                  >
                    <Printer className="size-3" aria-hidden="true" />
                    طباعة
                  </button>
                </div>
              </div>

              <div className="rounded-xl bg-[var(--surface-muted)]/50 p-4 border border-[var(--border)] text-xs leading-relaxed whitespace-pre-line font-serif">
                {generatedLetter}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Mode 3: Penalty & Deduction Calculator */}
      {mode === 'calculator' && (
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          <div className="card p-4 border border-[var(--border)] space-y-3">
            <h4 className="text-xs font-black text-[var(--text)] flex items-center gap-1.5">
              <Calculator className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
              محاكي احتساب الخصم والجزاء القانوني
            </h4>

            <div>
              <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">
                الراتب الأساسي الشهري للموظف (ج.م)
              </label>
              <input
                type="number"
                min={3000}
                max={100000}
                step={500}
                value={calcSalary}
                onChange={(e) => setCalcSalary(Math.max(1000, Number(e.target.value)))}
                className="input w-full text-xs tabular font-bold"
              />
            </div>

            <div>
              <label className="text-[11px] font-bold block mb-1 text-[var(--text-muted)]">
                نوع المخالفة وفق لائحة الجزاءات
              </label>
              <select
                value={penaltyType}
                onChange={(e) => setPenaltyType(e.target.value as typeof penaltyType)}
                className="input w-full text-xs"
              >
                <option value="late_1">تأخير للمرة الأولى خلال الشهر (إنذار)</option>
                <option value="late_2">تأخير للمرة الثانية خلال الشهر (خصم 25%)</option>
                <option value="late_3">تأخير للمرة الثالثة خلال الشهر (خصم 50%)</option>
                <option value="absence_1">غياب يوم كامل بدون إذن (خصم يوم كامل 100%)</option>
                <option value="absence_2">تكرار الغياب بدون إذن للمرة الثانية (خصم يومين 200%)</option>
                <option value="no_checkout">عدم تسجيل بصمة انصراف دون إثبات مأمورية</option>
              </select>
            </div>
          </div>

          {/* Results Card */}
          <div className="card p-5 border-2 border-[var(--brand-primary)]/40 bg-gradient-to-br from-[var(--surface)] to-[var(--surface-muted)] space-y-4 shadow-sm">
            <div className="flex items-center justify-between border-b border-[var(--border)] pb-3">
              <div>
                <span className="text-[11px] text-[var(--text-muted)] block">قيمة الخصم المالي المقترح</span>
                <span className="text-3xl font-black text-rose-600 dark:text-rose-400 tabular">
                  {calcResult.deductedAmount} <span className="text-sm font-bold">ج.م</span>
                </span>
              </div>
              <div className="text-left">
                <span className="text-[11px] text-[var(--text-muted)] block">النسبة المعتمدة</span>
                <span className="rounded-full bg-rose-500/10 text-rose-600 px-2.5 py-1 text-xs font-black border border-rose-500/20">
                  {calcResult.deductionFactor === 0 ? 'بدون خصم مالي' : `${calcResult.deductionFactor} يوم عمل`}
                </span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="bg-[var(--surface)] p-2.5 rounded-xl border border-[var(--border)]">
                <span className="text-[10px] text-[var(--text-muted)] block">أجر اليوم (أساسي/30)</span>
                <span className="font-bold tabular text-sm">{calcResult.dailyRate} ج.م</span>
              </div>
              <div className="bg-[var(--surface)] p-2.5 rounded-xl border border-[var(--border)]">
                <span className="text-[10px] text-[var(--text-muted)] block">أجر الساعة (يومي/8)</span>
                <span className="font-bold tabular text-sm">{calcResult.hourlyRate} ج.م</span>
              </div>
            </div>

            <div className="space-y-2 border-t border-[var(--border)] pt-3 text-xs">
              <div>
                <span className="font-bold text-[var(--text)] block mb-0.5">البند اللائحي:</span>
                <p className="text-[var(--text-muted)] leading-relaxed text-[11px]">{calcResult.ruleText}</p>
              </div>
              <div>
                <span className="font-bold text-[var(--brand-primary)] block mb-0.5">التوجيه الإداري الموصى به:</span>
                <p className="text-[var(--text-muted)] leading-relaxed text-[11px]">{calcResult.recommendation}</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="border-t border-[var(--border)] bg-[var(--surface-muted)]/50 px-4 py-2.5 flex items-center justify-between text-[11px] text-[var(--text-muted)]">
        <span className="flex items-center gap-1.5">
          <Sparkles className="size-3 text-[var(--brand-primary)]" aria-hidden="true" />
          نظام تشغيل وإدارة الموارد البشرية الذكي
        </span>
        <span className="font-mono text-[10px]">Alt + C</span>
      </div>
    </aside>
  );
}
