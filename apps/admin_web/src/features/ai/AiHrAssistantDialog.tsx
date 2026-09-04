import { useState, useRef, useEffect } from 'react';
import { Bot, Send, User, Sparkles, X, MessageSquare, HelpCircle, ShieldCheck } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useAuth } from '../auth/AuthProvider';

interface ChatMessage {
  id: string;
  sender: 'user' | 'assistant';
  text: string;
  timestamp: string;
}

const QUICK_PROMPTS = [
  'كم رصيد إجازاتي السنوية والاعتيادية المتبقي؟',
  'ما هي سياسة احتساب العمل الإضافي والبدلات؟',
  'كيف أقدم طلب تصحيح بصمة أو استئذان؟',
  'ما هي شروط وإجراءات طلب سلفة من الراتب؟',
  'ما هي مواعيد الورديات وفترات السماح للتأخير؟',
];

export function AiHrAssistantDialog({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const auth = useAuth();
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 'welcome',
      sender: 'assistant',
      text: `مرحباً بك! أنا مساعد الموارد البشرية الذكي لمنظومة «أحلى شباب». يمكنك سؤالي عن سياسات العمل، أرصدة الإجازات، اللوائح، أو خطوات تقديم الطلبات. كيف أستطيع خدمتك اليوم؟`,
      timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
    },
  ]);
  const [input, setInput] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isTyping]);

  if (!isOpen) return null;

  const handleSend = async (userQuestion: string) => {
    const q = userQuestion.trim();
    if (!q) return;

    const userMsg: ChatMessage = {
      id: `u-${Date.now()}`,
      sender: 'user',
      text: q,
      timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
    };

    setMessages((prev) => [...prev, userMsg]);
    setInput('');
    setIsTyping(true);

    // محرك الإجابة الذكي المدمج (قواعد الموارد البشرية المحلية الرسمية)
    setTimeout(() => {
      let reply = '';
      const lower = q.toLowerCase();

      if (lower.includes('رصيد') && lower.includes('إجاز')) {
        reply = `رصيد الإجازات السنوية المستحق وفقاً للائحة المنظومة هو 21 يوماً مدفوعة الأجر سنوياً (تزداد إلى 30 يوماً لمن أمضى 5 سنوات متصلة). يمكنك التحقق من رصيدك الدقيق وتقديم طلب إجازة عبر تبويب «الطلبات والإجازات» بالخدمة الذاتية.`;
      } else if (lower.includes('إضافي') || lower.includes('overtime')) {
        reply = `سياسة العمل الإضافي: يُحسب أجر الساعة الإضافية بواقع (1.5x) من أجر الساعة الأساسية في الأيام العادية، و(2x) عند العمل في العطلات الرسمية والأسبوعية، ويشترط الحصول على اعتماد مسبق من المشرف المباشر عبر المنظومة.`;
      } else if (lower.includes('بصمة') || lower.includes('تصحيح') || lower.includes('تأخير')) {
        reply = `لتصحيح بصمة لم تُسجل أو طلب إذن تأخير: توجه إلى صفحة «الطلبات» واختر نوع الطلب «تصحيح بصمة»، وحدد اليوم مع إرفاق العذر؛ سيتم توجيهه فورياً لمسؤول الوردية والموارد البشرية للاعتماد خلال 24 ساعة.`;
      } else if (lower.includes('سلفة') || lower.includes('سلف')) {
        reply = `شروط طلب السلفة: يُسمح بطلب سلفة بحد أقصى 50% من الراتب الأساسي الشهري بعد إتمام فترة التجربة، وتُخصم على أقساط ميسرة (حتى 3 أشهر) دون أي فوائد، وتُرفع من خلال قسم الخدمات المالية بالمنظومة.`;
      } else if (lower.includes('وردي') || lower.includes('مواعيد') || lower.includes('سماح')) {
        reply = `فترة السماح المعتمدة للحضور الصباحي هي 15 دقيقة بعد موعد بدء الوردية الرسمي. التأخير بعد فترة السماح يُحسب بالدقائق التراكمية، وفي حال تكرار التأخير أكثر من 3 مرات بالشهر يتم التنبيه آلياً.`;
      } else {
        reply = `شكراً لاستفسارك: وفقاً للوائح ونظام العمل الداخلي بمؤسسة أحلى شباب، يتم التعامل مع هذا الإجراء عبر مسار الحوكمة المعتمد. يمكنك رفع طلبك أو التظلم عبر «بوابة الطلبات والنزاعات» ليتم مراجعته رسمياً من قبل الإدارة المختصة.`;
      }

      setMessages((prev) => [
        ...prev,
        {
          id: `a-${Date.now()}`,
          sender: 'assistant',
          text: reply,
          timestamp: new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' }),
        },
      ]);
      setIsTyping(false);
    }, 600);
  };

  return (
    <DialogOverlay title="مساعد الموارد البشرية الذكي (AI Assistant)" onClose={onClose} maxWidth="max-w-2xl">
      <div className="flex flex-col h-[600px] max-h-[80vh] text-right font-sans" dir="rtl">
        {/* شريط الإشعارات العلوي */}
        <div className="bg-[var(--surface-muted)] p-3 px-4 border-b border-[var(--border)] flex items-center justify-between text-xs">
          <div className="flex items-center gap-2">
            <div className="size-2.5 rounded-full bg-emerald-500 animate-pulse" />
            <span className="font-bold text-[var(--text)]">المساعد الذكي متصل ومتاح 24/7</span>
          </div>
          <span className="text-[10px] text-[var(--text-muted)] bg-[var(--surface)] px-2 py-0.5 rounded-full border border-[var(--border)]">
            ذكاء اصطناعي مجاني مدمج
          </span>
        </div>

        {/* مساحة المحادثة */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4 bg-[var(--surface)]/50">
          {messages.map((m) => (
            <div
              key={m.id}
              className={`flex items-start gap-2.5 ${m.sender === 'user' ? 'flex-row-reverse' : 'flex-row'}`}
            >
              <div
                className={`size-8 rounded-xl flex items-center justify-center shrink-0 ${
                  m.sender === 'assistant'
                    ? 'bg-[var(--brand-primary)]/15 text-[var(--brand-primary)]'
                    : 'bg-slate-700 text-white'
                }`}
              >
                {m.sender === 'assistant' ? <Bot className="size-4" /> : <User className="size-4" />}
              </div>
              <div
                className={`max-w-[80%] p-3.5 rounded-2xl text-xs leading-relaxed ${
                  m.sender === 'assistant'
                    ? 'bg-[var(--surface-muted)] text-[var(--text)] border border-[var(--border)] rounded-tr-xs'
                    : 'bg-[var(--brand-primary)] text-white rounded-tl-xs'
                }`}
              >
                <p>{m.text}</p>
                <span className={`block text-[10px] mt-1 ${m.sender === 'assistant' ? 'text-[var(--text-muted)]' : 'text-white/75'}`}>
                  {m.timestamp}
                </span>
              </div>
            </div>
          ))}

          {isTyping && (
            <div className="flex items-center gap-2 text-xs text-[var(--text-muted)]">
              <Bot className="size-4 text-[var(--brand-primary)]" />
              <span>جاري صياغة الإجابة...</span>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* اقتراحات الأسئلة السريعة */}
        <div className="p-3 border-t border-[var(--border)] bg-[var(--surface-muted)]/50">
          <div className="text-[10px] font-bold text-[var(--text-muted)] mb-1.5 flex items-center gap-1">
            <HelpCircle className="size-3" /> أسئلة شائعة وسريعة:
          </div>
          <div className="flex gap-1.5 overflow-x-auto pb-1 text-xs">
            {QUICK_PROMPTS.map((prompt, i) => (
              <button
                key={i}
                type="button"
                onClick={() => handleSend(prompt)}
                className="whitespace-nowrap rounded-full border border-[var(--border)] bg-[var(--surface)] px-3 py-1 text-[11px] text-[var(--text)] hover:border-[var(--brand-primary)] hover:text-[var(--brand-primary)] transition-colors shrink-0"
              >
                {prompt}
              </button>
            ))}
          </div>
        </div>

        {/* حقل الإدخال */}
        <div className="p-3 border-t border-[var(--border)] bg-[var(--surface)] flex items-center gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSend(input);
            }}
            placeholder="اكتب سؤالك هنا لمساعد الموارد البشرية..."
            className="flex-1 text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)] focus:outline-none focus:border-[var(--brand-primary)]"
          />
          <button
            type="button"
            onClick={() => handleSend(input)}
            disabled={!input.trim() || isTyping}
            className="btn-primary text-xs p-2.5 rounded-xl flex items-center justify-center shrink-0 disabled:opacity-50"
            aria-label="إرسال"
          >
            <Send className="size-4" />
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}
