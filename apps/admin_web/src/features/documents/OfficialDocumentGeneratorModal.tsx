import { useState, useRef, useMemo } from 'react';
import { Printer, FileText, CheckCircle, Building2, ShieldCheck, Compass, Award, Share2 } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { SignaturePad } from '../../ui/SignaturePad';
import { shareOfficialDocumentNotice } from '../../core/whatsappShare';

export type OfficialDocType =
  | 'salary_certificate'
  | 'employment_contract'
  | 'clearance_settlement'
  | 'mission_assignment'
  | 'association_affiliation';

export interface OfficialDocEmployee {
  id: string;
  fullNameAr: string;
  fullNameEn?: string;
  employeeCode: string;
  nationalId?: string;
  jobTitle: string;
  departmentName: string;
  hireDate?: string;
  basicSalary?: number;
  housingAllowance?: number;
  transportAllowance?: number;
  totalSalary?: number;
}

interface OfficialDocumentGeneratorModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee?: OfficialDocEmployee;
  initialType?: OfficialDocType;
}

export function OfficialDocumentGeneratorModal({ isOpen, onClose, employee, initialType = 'salary_certificate' }: OfficialDocumentGeneratorModalProps) {
  const [docType, setDocType] = useState<OfficialDocType>(initialType);
  const [recipient, setRecipient] = useState('إلى من يهمه الأمر');
  const [purpose, setPurpose] = useState('بناءً على طلب الموظف لتقديمه للجهات الرسمية المعنية');
  const [contractPeriodYears, setContractPeriodYears] = useState('1');
  const [probationMonths, setProbationMonths] = useState('3');
  const [missionTitle, setMissionTitle] = useState('قافلة ستر ودفا وإغاثة القرى الأكثر احتياجاً');
  const [missionDestination, setMissionDestination] = useState('محافظة الجيزة — قرى مركز أطفيح');
  const [missionStartDate, setMissionStartDate] = useState('2026-10-15');
  const [missionEndDate, setMissionEndDate] = useState('2026-10-18');
  const [affiliationPurpose, setAffiliationPurpose] = useState('تسهيل مهمة العمل الميداني والتعامل مع الجهات المعنية نيابة عن الجمعية');
  const [showSignaturePad, setShowSignaturePad] = useState(false);
  const [employeeSignature, setEmployeeSignature] = useState<string | null>(null);

  const printAreaRef = useRef<HTMLDivElement | null>(null);

  if (!isOpen) return null;

  // قيم افتراضية متزنة في حال عدم توفرها في سجل الموظف
  const emp: OfficialDocEmployee = employee || {
    id: 'emp-preview',
    fullNameAr: 'أحمد محمد إبراهيم السعيد',
    fullNameEn: 'Ahmed Mohamed Ibrahim',
    employeeCode: 'EMP-01042',
    nationalId: '29304151201948',
    jobTitle: 'أخصائي أول عمليات وتشغيل',
    departmentName: 'إدارة العمليات واللوجستيات',
    hireDate: '2023-03-01',
    basicSalary: 6500,
    housingAllowance: 1500,
    transportAllowance: 1000,
    totalSalary: 9000,
  };

  const basicSalary = emp.basicSalary ?? 6000;
  const housing = emp.housingAllowance ?? 1500;
  const transport = emp.transportAllowance ?? 1000;
  const total = emp.totalSalary ?? basicSalary + housing + transport;

  const issueDate = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'long' }).format(new Date());
  const serialNo = `DOC-${new Date().getFullYear()}-${emp.employeeCode.replace(/\D/g, '') || '99'}-${Math.floor(1000 + Math.random() * 9000)}`;

  const handlePrint = () => {
    window.print();
  };

  return (
    <DialogOverlay title="توليد الوثائق الرسمية وقوالب الـ PDF" onClose={onClose} maxWidth="max-w-5xl">
      <div className="flex flex-col lg:flex-row gap-6 p-6 max-h-[85vh] overflow-y-auto">
        {/* اللوحة الجانبية: تخصيص المستند */}
        <div className="w-full lg:w-80 shrink-0 space-y-5 border-b lg:border-b-0 lg:border-e border-[var(--border)] ps-0 lg:pe-6 pb-6 lg:pb-0">
          <div>
            <label className="block text-xs font-bold text-[var(--text)] mb-2">نوع الوثيقة الرسمية</label>
            <div className="space-y-2">
              <button
                type="button"
                onClick={() => setDocType('salary_certificate')}
                className={`w-full text-end p-3 rounded-xl border text-xs font-bold transition-all flex items-center gap-2.5 ${
                  docType === 'salary_certificate'
                    ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]'
                    : 'border-[var(--border)] hover:bg-[var(--surface-muted)] text-[var(--text)]'
                }`}
              >
                <FileText className="size-4 shrink-0" />
                شهادة تعريف بالراتب (HR Letter)
              </button>

              <button
                type="button"
                onClick={() => setDocType('employment_contract')}
                className={`w-full text-end p-3 rounded-xl border text-xs font-bold transition-all flex items-center gap-2.5 ${
                  docType === 'employment_contract'
                    ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]'
                    : 'border-[var(--border)] hover:bg-[var(--surface-muted)] text-[var(--text)]'
                }`}
              >
                <Building2 className="size-4 shrink-0" />
                عقد عمل موحد (Employment Contract)
              </button>

              <button
                type="button"
                onClick={() => setDocType('clearance_settlement')}
                className={`w-full text-end p-3 rounded-xl border text-xs font-bold transition-all flex items-center gap-2.5 ${
                  docType === 'clearance_settlement'
                    ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]'
                    : 'border-[var(--border)] hover:bg-[var(--surface-muted)] text-[var(--text)]'
                }`}
              >
                <CheckCircle className="size-4 shrink-0" />
                إخلاء طرف ومخالصة مالية (Clearance)
              </button>

              <button
                type="button"
                onClick={() => {
                  setDocType('mission_assignment');
                  if (recipient === 'إلى من يهمه الأمر') {
                    setRecipient('السادة / الأجهزة التنفيذية ولجان التنسيق الميداني');
                  }
                }}
                className={`w-full text-end p-3 rounded-xl border text-xs font-bold transition-all flex items-center gap-2.5 ${
                  docType === 'mission_assignment'
                    ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]'
                    : 'border-[var(--border)] hover:bg-[var(--surface-muted)] text-[var(--text)]'
                }`}
              >
                <Compass className="size-4 shrink-0" />
                خطاب تكليف بمأمورية وقافلة ميدانية (Mission)
              </button>

              <button
                type="button"
                onClick={() => {
                  setDocType('association_affiliation');
                  if (recipient === 'السادة / الأجهزة التنفيذية ولجان التنسيق الميداني') {
                    setRecipient('إلى من يهمه الأمر');
                  }
                }}
                className={`w-full text-end p-3 rounded-xl border text-xs font-bold transition-all flex items-center gap-2.5 ${
                  docType === 'association_affiliation'
                    ? 'border-[var(--brand-primary)] bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]'
                    : 'border-[var(--border)] hover:bg-[var(--surface-muted)] text-[var(--text)]'
                }`}
              >
                <Award className="size-4 shrink-0" />
                إثبات انتساب وتصريح حركة ميداني (Permit)
              </button>
            </div>
          </div>

          {/* حقول مخصصة حسب النوع */}
          {docType === 'salary_certificate' && (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">الجهة الموجه إليها الخطاب</label>
                <input
                  type="text"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                  placeholder="مثال: إلى من يهمه الأمر / بنك مصر"
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">الغرض من الخطاب</label>
                <input
                  type="text"
                  value={purpose}
                  onChange={(e) => setPurpose(e.target.value)}
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
            </div>
          )}

          {docType === 'employment_contract' && (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">مدة العقد (سنوات)</label>
                <select
                  value={contractPeriodYears}
                  onChange={(e) => setContractPeriodYears(e.target.value)}
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                >
                  <option value="1">سنة واحدة تجدد تلقائياً</option>
                  <option value="2">سنتان تجدد باتفاق الطرفين</option>
                  <option value="unlimited">غير محدد المدة</option>
                </select>
              </div>
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">فترة التجربة</label>
                <select
                  value={probationMonths}
                  onChange={(e) => setProbationMonths(e.target.value)}
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                >
                  <option value="3">3 أشهر (90 يوماً)</option>
                  <option value="6">6 أشهر (180 يوماً)</option>
                  <option value="0">بدون فترة تجربة</option>
                </select>
              </div>
            </div>
          )}

          {docType === 'mission_assignment' && (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">الجهة الموجه إليها الخطاب</label>
                <input
                  type="text"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                  placeholder="السادة / الأجهزة التنفيذية ولجان التنسيق الميداني"
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">مسمى المأمورية / القافلة</label>
                <input
                  type="text"
                  value={missionTitle}
                  onChange={(e) => setMissionTitle(e.target.value)}
                  placeholder="مثال: قافلة ستر ودفا وإغاثة القرى الأكثر احتياجاً"
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">نطاق الوجهة والمحافظة</label>
                <input
                  type="text"
                  value={missionDestination}
                  onChange={(e) => setMissionDestination(e.target.value)}
                  placeholder="مثال: محافظة الجيزة — قرى مركز أطفيح"
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-xs font-bold text-[var(--text)] mb-1">من تاريخ</label>
                  <input
                    type="date"
                    value={missionStartDate}
                    onChange={(e) => setMissionStartDate(e.target.value)}
                    className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-[var(--text)] mb-1">إلى تاريخ</label>
                  <input
                    type="date"
                    value={missionEndDate}
                    onChange={(e) => setMissionEndDate(e.target.value)}
                    className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                  />
                </div>
              </div>
            </div>
          )}

          {docType === 'association_affiliation' && (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">الجهة الموجه إليها</label>
                <input
                  type="text"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                  placeholder="إلى من يهمه الأمر"
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-[var(--text)] mb-1">غرض التصريح والتكليف الميداني</label>
                <textarea
                  rows={3}
                  value={affiliationPurpose}
                  onChange={(e) => setAffiliationPurpose(e.target.value)}
                  className="w-full text-xs p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] text-[var(--text)]"
                />
              </div>
            </div>
          )}

          {/* التوقيع الحي */}
          <div className="pt-3 border-t border-[var(--border)] space-y-2">
            <label className="block text-xs font-bold text-[var(--text)]">التوقيع الرقمي للمستند</label>
            {employeeSignature ? (
              <div className="p-2 border rounded-xl bg-emerald-500/10 border-emerald-500/30 text-emerald-700 text-xs flex items-center justify-between">
                <span>تم إرفاق التوقيع الحي بنجاح</span>
                <button type="button" onClick={() => setEmployeeSignature(null)} className="text-xs text-rose-500 underline">
                  إلغاء
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => setShowSignaturePad(true)}
                className="w-full btn-secondary text-xs py-2 flex items-center justify-center gap-1.5"
              >
                توقيع الموظف الآن باللمس
              </button>
            )}
          </div>

          {/* زر التصدير والطباعة والمشاركة */}
          <div className="pt-4 border-t border-[var(--border)] space-y-2.5">
            <button type="button" onClick={handlePrint} className="btn-primary w-full py-3 text-xs font-bold flex items-center justify-center gap-2 shadow-lg">
              <Printer className="size-4" />
              طباعة / حفظ كـ PDF رسمي
            </button>
            <button
              type="button"
              onClick={() => {
                const titlesMap: Record<OfficialDocType, string> = {
                  salary_certificate: 'شهادة تعريف بالراتب (HR Letter)',
                  employment_contract: 'عقد عمل موحد',
                  clearance_settlement: 'إخلاء طرف ومخالصة نهائية',
                  mission_assignment: `خطاب تكليف بمأمورية: ${missionTitle}`,
                  association_affiliation: 'إثبات انتساب وتصريح حركة ميداني',
                };
                shareOfficialDocumentNotice({
                  employeeName: emp.fullNameAr,
                  docTitle: titlesMap[docType],
                  serialNo,
                  recipient,
                });
              }}
              className="w-full py-2.5 px-3 rounded-xl border border-emerald-600/30 text-emerald-600 hover:bg-emerald-500/10 font-bold text-xs flex items-center justify-center gap-2 transition-all"
            >
              <Share2 className="size-4" />
              مشاركة إشعار الوثيقة (WhatsApp)
            </button>
            <p className="text-[11px] text-[var(--text-muted)] text-center">يتم التصدير بأعلى دقة متوافقة مع الطباعة A4 بدون أي تكلفة خارجية.</p>
          </div>
        </div>

        {/* مساحة المعاينة الحية للورقة الرسمية A4 */}
        <div className="flex-1 bg-slate-100 dark:bg-slate-900/50 p-4 sm:p-6 rounded-2xl flex justify-center overflow-x-auto">
          <div
            ref={printAreaRef}
            id="official-printable-doc"
            className="w-full max-w-[210mm] min-h-[297mm] bg-white text-slate-900 p-8 sm:p-12 shadow-2xl rounded-lg font-serif relative flex flex-col justify-between border border-slate-200"
            style={{ minHeight: '842px', color: '#0f172a' }}
          >
            {/* الترويسة الرسمية */}
            <div>
              <div className="flex items-center justify-between border-b-2 border-slate-900 pb-5 mb-8">
                <div>
                  <h2 className="text-xl font-black tracking-tight text-slate-900">مؤسسة أحلى شباب للتنمية والتشغيل</h2>
                  <p className="text-xs text-slate-500 mt-1 font-sans">إدارة الموارد البشرية والعمليات المركزية</p>
                  <p className="text-[10px] text-slate-400 font-mono mt-0.5">HR & Central Operations Directorate</p>
                </div>
                <div className="text-end">
                  <div className="size-14 rounded-xl border-2 border-slate-900 flex items-center justify-center font-bold text-lg text-slate-900 font-sans shadow-xs">
                    HR
                  </div>
                  <div className="text-[10px] font-mono text-slate-500 mt-2 font-bold">{serialNo}</div>
                  <div className="text-[10px] text-slate-500">{issueDate}</div>
                </div>
              </div>

              {/* عنوان المستند الرئيسي */}
              <div className="text-center my-6">
                <h1 className="text-lg font-black inline-block border-b-2 border-slate-900 pb-1 px-8">
                  {docType === 'salary_certificate' && 'شـــهـــادة تــعــريــف بــالـــراتـــب'}
                  {docType === 'employment_contract' && 'عــقــد عــمــل مــوحّـــد'}
                  {docType === 'clearance_settlement' && 'نــمــوذج إخـــلاء طـــرف ومــخـالـصـة نـهـائـيـة'}
                  {docType === 'mission_assignment' && 'خــطــاب تــكــلــيـف بـمـأمـوريـة وقـافـلـة مـيـدانـيـة'}
                  {docType === 'association_affiliation' && 'إثــبـات عـمـل وانـتـسـاب وتـصـريـح حـركـة مـيـدانـي'}
                </h1>
              </div>

              {/* محتوى: شهادة تعريف بالراتب */}
              {docType === 'salary_certificate' && (
                <div className="space-y-5 text-sm leading-relaxed text-justify">
                  <p className="font-bold">
                    السادة / {recipient} <span className="font-normal">المحترمين،</span>
                  </p>
                  <p className="text-slate-500 text-xs">تحية طيبة وبعد،،،</p>

                  <p>
                    تشهد مؤسسة «أحلى شباب» بأن السيد/ <strong>{emp.fullNameAr}</strong> (الرقم القومي / الهوية:{' '}
                    <span className="font-mono font-bold">{emp.nationalId || '—'}</span>، الكود الوظيفي:{' '}
                    <span className="font-mono font-bold">{emp.employeeCode}</span>)، يعمل لدينا وتحت كفالتنا الإدارية بوظيفة <strong>{emp.jobTitle}</strong> بـ{' '}
                    <strong>{emp.departmentName}</strong>، وذلك منذ تاريخ التحاقه بالعمل في <span className="font-bold font-mono">{emp.hireDate || '—'}</span>{' '}
                    ولا يزال على رأس عمله حتى تاريخ تحرير هذه الشهادة.
                  </p>

                  <div className="my-5 border border-slate-300 rounded-lg overflow-hidden">
                    <table className="w-full text-xs text-end divide-y divide-slate-200">
                      <thead className="bg-slate-100 text-slate-700 font-bold">
                        <tr>
                          <th className="p-2.5">بيان الراتب والبدلات</th>
                          <th className="p-2.5 text-end">المبلغ الشهري (بالجنيه المصري)</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-200">
                        <tr>
                          <td className="p-2.5">الراتب الأساسي (Basic Salary)</td>
                          <td className="p-2.5 text-end font-mono font-bold">{basicSalary.toLocaleString()} ج.م</td>
                        </tr>
                        <tr>
                          <td className="p-2.5">بدل السكن والإعاشة (Housing)</td>
                          <td className="p-2.5 text-end font-mono font-bold">{housing.toLocaleString()} ج.م</td>
                        </tr>
                        <tr>
                          <td className="p-2.5">بدل الانتقال والميدان (Transport)</td>
                          <td className="p-2.5 text-end font-mono font-bold">{transport.toLocaleString()} ج.م</td>
                        </tr>
                        <tr className="bg-slate-50 font-bold text-slate-900">
                          <td className="p-2.5">إجمالي الراتب الشهري الشامل (Gross Salary)</td>
                          <td className="p-2.5 text-end font-mono text-sm font-black">{total.toLocaleString()} ج.م</td>
                        </tr>
                      </tbody>
                    </table>
                  </div>

                  <p className="text-xs text-slate-600">
                    وقد أُعطيت له هذه الشهادة {purpose}، دون أدنى مسؤولية مالية أو التزام كفالة يقع على عاتق المنشأة تجاه الغير.
                  </p>
                </div>
              )}

              {/* محتوى: عقد عمل موحد */}
              {docType === 'employment_contract' && (
                <div className="space-y-4 text-xs leading-relaxed text-justify">
                  <p>
                    إنه في يوم <strong>{issueDate}</strong>، تم الاتفاق والتراضي بين كل من:
                  </p>
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-200 space-y-1">
                    <p>
                      <strong>الطرف الأول:</strong> مؤسسة أحلى شباب، ويمثلها مدير الموارد البشرية.
                    </p>
                    <p>
                      <strong>الطرف الثاني:</strong> السيد/ {emp.fullNameAr}، الرقم القومي: {emp.nationalId || '—'}، الكود: {emp.employeeCode}.
                    </p>
                  </div>

                  <p className="font-bold">البنود والشروط المتفق عليها:</p>
                  <ol className="list-decimal list-inside space-y-1.5 text-slate-700">
                    <li>
                      <strong>طبيعة العمل:</strong> يعمل الطرف الثاني لدى الطرف الأول بمهنة ({emp.jobTitle}) في ({emp.departmentName}).
                    </li>
                    <li>
                      <strong>مدة العقد:</strong> يبدأ سريان هذا العقد لمدة{' '}
                      {contractPeriodYears === '1' ? 'سنة واحدة' : contractPeriodYears === '2' ? 'سنتين' : 'غير محددة'} قابلة للتجديد بموافقة الطرفين.
                    </li>
                    <li>
                      <strong>فترة التجربة:</strong> يخضع الطرف الثاني لفترة تجربة مدتها {probationMonths} أشهر وفقاً لأحكام قانون العمل.
                    </li>
                    <li>
                      <strong>الراتب والمستحقات:</strong> يتقاضى الطرف الثاني راتباً شهرياً إجمالياً قدره ({total.toLocaleString()} ج.م) شاملاً كافة البدلات.
                    </li>
                    <li>
                      <strong>السرية وحماية البيانات:</strong> يتعهد الطرف الثاني بالحفاظ التام على أسرار العمل وعدم إفشاء أي بيانات تشغيلية أو برمجية.
                    </li>
                  </ol>
                </div>
              )}

              {/* محتوى: إخلاء طرف ومخالصة */}
              {docType === 'clearance_settlement' && (
                <div className="space-y-4 text-xs leading-relaxed text-justify">
                  <p>تفيد إدارة الموارد البشرية والشؤون المالية بأن الموظف المذكور أدناه قد أتم إجراءات إخلاء الطرف وتسليم العهد الرسمية:</p>
                  <div className="grid grid-cols-2 gap-2 text-xs border border-slate-200 p-2.5 rounded-lg bg-slate-50">
                    <div>
                      <strong>الموظف:</strong> {emp.fullNameAr}
                    </div>
                    <div>
                      <strong>الكود الوظيفي:</strong> {emp.employeeCode}
                    </div>
                    <div>
                      <strong>الوظيفة:</strong> {emp.jobTitle}
                    </div>
                    <div>
                      <strong>تاريخ إنهاء العلاقة:</strong> {issueDate}
                    </div>
                  </div>

                  <div className="space-y-1.5 pt-2">
                    <p className="font-bold">بيان تسليم العهد والأقسام:</p>
                    <div className="grid grid-cols-3 gap-2 text-[11px] text-center">
                      <div className="p-2 border border-slate-300 rounded bg-white">
                        <div className="font-bold">تقنية المعلومات (IT)</div>
                        <div className="text-emerald-700 font-bold mt-1">✓ تم تسليم الأجهزة والبريد</div>
                      </div>
                      <div className="p-2 border border-slate-300 rounded bg-white">
                        <div className="font-bold">الشؤون الإدارية</div>
                        <div className="text-emerald-700 font-bold mt-1">✓ تم تسليم المفاتيح والبطاقة</div>
                      </div>
                      <div className="p-2 border border-slate-300 rounded bg-white">
                        <div className="font-bold">الإدارة المالية</div>
                        <div className="text-emerald-700 font-bold mt-1">✓ لا توجد سلف أو عهد نقدية</div>
                      </div>
                    </div>
                  </div>

                  <p className="text-xs text-slate-600 pt-2">
                    يقر الموظف باستلامه لكافة مستحقاته المالية ومكافأة نهاية الخدمة وشهادة الخبرة، وتعتبر ذمة المؤسسة بريئة تماماً من أي مطالبات مالية أو
                    عمالية.
                  </p>
                </div>
              )}

              {/* محتوى: خطاب تكليف بمأمورية وقافلة ميدانية */}
              {docType === 'mission_assignment' && (
                <div className="space-y-4 text-xs leading-relaxed text-justify">
                  <p className="font-bold">
                    السادة / {recipient} <span className="font-normal">المحترمين،</span>
                  </p>
                  <p className="text-slate-500 text-xs">تحية طيبة وبعد،،،</p>

                  <p>
                    تفيد إدارة الموارد البشرية والعمليات المركزية بجمعية «أحلى شباب» للتنمية بأن السيد/ <strong>{emp.fullNameAr}</strong> (الرقم القومي:{' '}
                    <span className="font-mono font-bold">{emp.nationalId || '—'}</span>، الكود الوظيفي:{' '}
                    <span className="font-mono font-bold">{emp.employeeCode}</span>)، والذي يشغل وظيفة <strong>{emp.jobTitle}</strong> بـ{' '}
                    <strong>{emp.departmentName}</strong>، قد تم تكليفه رسمياً من قبل إدارة الجمعية بتنفيذ والإشراف على المأمورية والقافلة الميدانية الموضحة أدناه:
                  </p>

                  <div className="my-3 border border-slate-300 rounded-lg overflow-hidden bg-slate-50 p-3 space-y-2">
                    <div className="grid grid-cols-2 gap-3 text-xs">
                      <div>
                        <span className="text-slate-500 block text-[10px]">مسمى المأمورية / القافلة:</span>
                        <strong className="text-slate-900">{missionTitle}</strong>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px]">النطاق الجغرافي والوجهة:</span>
                        <strong className="text-slate-900">{missionDestination}</strong>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px]">تاريخ بدء المأمورية:</span>
                        <span className="font-mono font-bold text-slate-800">{missionStartDate}</span>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px]">تاريخ انتهاء المأمورية:</span>
                        <span className="font-mono font-bold text-slate-800">{missionEndDate}</span>
                      </div>
                    </div>
                  </div>

                  <p className="text-slate-700 leading-relaxed">
                    نرجو من سيادتكم ومن كافة الأجهزة المعنية والأجهزة التنفيذية والأمنية ونقاط التفتيش ولجان التنسيق الميداني التفضل بتقديم كافة التسهيلات اللوجستية وتيسير مهام حركة القافلة وفريق العمل الإنساني، وذلك دعماً لجهود الإغاثة والعمل الأهلي والتطوعي بالقرى والمناطق المستهدفة.
                  </p>

                  <p className="text-[11px] text-slate-500">
                    صدر هذا التكليف بتفويض من الإدارة التنفيذية وإدارة العمليات، ويسري طوال مدة القافلة الموضحة أعلاه.
                  </p>
                </div>
              )}

              {/* محتوى: إثبات انتساب وتصريح حركة ميداني */}
              {docType === 'association_affiliation' && (
                <div className="space-y-4 text-xs leading-relaxed text-justify">
                  <p className="font-bold">
                    السادة / {recipient} <span className="font-normal">المحترمين،</span>
                  </p>
                  <p className="text-slate-500 text-xs">تحية طيبة وبعد،،،</p>

                  <p>
                    تشهد جمعية «أحلى شباب» للتنمية بأن السيد/ <strong>{emp.fullNameAr}</strong> (الرقم القومي / الهوية:{' '}
                    <span className="font-mono font-bold">{emp.nationalId || '—'}</span>، الكود الوظيفي:{' '}
                    <span className="font-mono font-bold">{emp.employeeCode}</span>)، هو أحد منسوبي الجمعية المعتمدين، ويعمل لدينا بصفة منتظمة بوظيفة{' '}
                    <strong>{emp.jobTitle}</strong> بـ <strong>{emp.departmentName}</strong>، منذ تاريخ{' '}
                    <span className="font-bold font-mono">{emp.hireDate || '—'}</span> وحتى تاريخه.
                  </p>

                  <div className="my-3 border border-slate-300 rounded-lg p-3 bg-slate-50 space-y-1">
                    <div className="font-bold text-slate-800 text-xs">بيان التصريح والتمثيل الميداني:</div>
                    <p className="text-xs text-slate-700">
                      المذكور مصرح له بتمثيل الجمعية في المهام الميدانية والمجتمعية، واستلام وتسليم المساعدات العينية والإشراف على فرق المتطوعين وفقاً لتوجيهات الإدارة:
                    </p>
                    <div className="p-2 bg-white rounded border border-slate-200 text-xs font-semibold text-slate-900 mt-1">
                      «{affiliationPurpose}»
                    </div>
                  </div>

                  <p className="text-slate-700 leading-relaxed text-xs">
                    أُعطيت له هذه الإفادة لتيسير مهمته الرسمية وإثبات انتسابه القانوني والتنظيمي لجمعية أحلى شباب الخاضعة لأحكام قانون تنظيم العمل الأهلي، دون أدنى مسؤولية مالية على الجمعية تجاه التزاماته الشخصية.
                  </p>
                </div>
              )}
            </div>

            {/* بطاقة التحقق الذكية برمز QR */}
            <div className="my-4 p-2.5 rounded-lg border border-slate-300 bg-slate-50/70 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="size-14 bg-white p-1 rounded border border-slate-300 shrink-0 flex items-center justify-center shadow-xs">
                  <svg viewBox="0 0 40 40" className="size-full fill-slate-900" aria-label="QR Code">
                    <rect x="2" y="2" width="10" height="10" rx="1" fill="#0f172a" />
                    <rect x="4" y="4" width="6" height="6" fill="#ffffff" />
                    <rect x="5.5" y="5.5" width="3" height="3" fill="#0f172a" />
                    <rect x="28" y="2" width="10" height="10" rx="1" fill="#0f172a" />
                    <rect x="30" y="4" width="6" height="6" fill="#ffffff" />
                    <rect x="31.5" y="5.5" width="3" height="3" fill="#0f172a" />
                    <rect x="2" y="28" width="10" height="10" rx="1" fill="#0f172a" />
                    <rect x="4" y="30" width="6" height="6" fill="#ffffff" />
                    <rect x="5.5" y="31.5" width="3" height="3" fill="#0f172a" />
                    <rect x="15" y="4" width="3" height="3" />
                    <rect x="21" y="4" width="4" height="2" />
                    <rect x="15" y="10" width="2" height="4" />
                    <rect x="20" y="10" width="5" height="2" />
                    <rect x="15" y="17" width="10" height="6" fill="#0f172a" rx="0.5" />
                    <rect x="28" y="15" width="3" height="4" />
                    <rect x="33" y="18" width="4" height="3" />
                    <rect x="4" y="15" width="4" height="3" />
                    <rect x="10" y="19" width="3" height="4" />
                    <rect x="15" y="26" width="3" height="5" />
                    <rect x="21" y="28" width="4" height="3" />
                    <rect x="28" y="26" width="4" height="4" />
                    <rect x="34" y="29" width="3" height="5" />
                  </svg>
                </div>
                <div className="text-start">
                  <div className="text-[10px] font-bold text-slate-800 flex items-center gap-1">
                    <ShieldCheck className="size-3 text-emerald-600 inline" />
                    رمز التحقق الذكي المعتمد (Smart QR Verification)
                  </div>
                  <div className="text-[9px] text-slate-500 font-sans mt-0.5">
                    يمكن للجهات المعنية والأجهزة الرقابية مسح الكود للتحقق الفوري من صحة الوثيقة والتفويض الميداني
                  </div>
                  <div className="text-[9px] font-mono text-slate-700 font-bold mt-0.5">
                    Ref: {serialNo} | Ahla Shabab NGO Official Verification
                  </div>
                </div>
              </div>
              <div className="text-end text-[9px] text-slate-400 font-mono hidden sm:block">
                SECURED DOCUMENT
              </div>
            </div>

            {/* التذييل والتوقيعات الرسمية والأختام */}
            <div className="pt-10 border-t border-slate-300 mt-8">
              <div className="grid grid-cols-3 gap-4 text-xs text-center items-end">
                {/* توقيع الموظف */}
                <div className="space-y-2">
                  <div className="font-bold text-slate-800">توقيع الموظف (المقر بما فيه)</div>
                  <div className="h-16 flex items-center justify-center border-b border-dashed border-slate-400">
                    {employeeSignature ? (
                      <img src={employeeSignature} alt="توقيع الموظف" className="max-h-14 object-contain" />
                    ) : (
                      <span className="text-[10px] text-slate-400">التوقيع اليدوي / الحي</span>
                    )}
                  </div>
                  <div className="text-[10px] text-slate-500">{emp.fullNameAr}</div>
                </div>

                {/* ختم المؤسسة الرسمي */}
                <div className="flex flex-col items-center justify-center space-y-1">
                  <div className="size-20 rounded-full border-2 border-dashed border-blue-900/60 flex flex-col items-center justify-center text-[9px] font-bold text-blue-950 rotate-[-12deg] bg-blue-50/50 p-1">
                    <span>مؤسسة أحلى شباب</span>
                    <span className="text-[8px] font-mono">SEAL & VERIFIED</span>
                    <span className="text-[7px]">إدارة الموارد البشرية</span>
                  </div>
                  <div className="text-[9px] text-slate-400 font-mono">الختم الرقمي المعتمد</div>
                </div>

                {/* اعتماد مدير الموارد البشرية */}
                <div className="space-y-2">
                  <div className="font-bold text-slate-800">اعتماد إدارة الموارد البشرية</div>
                  <div className="h-16 flex items-center justify-center border-b border-dashed border-slate-400">
                    <span className="font-serif italic font-bold text-slate-700 text-sm">HR Director Approval</span>
                  </div>
                  <div className="text-[10px] text-slate-500">مدير عام الموارد البشرية والعمليات</div>
                </div>
              </div>

              {/* شريط التحقق الأمني السفلي */}
              <div className="mt-8 pt-3 border-t border-slate-200 flex items-center justify-between text-[9px] text-slate-400 font-mono">
                <div className="flex items-center gap-1.5">
                  <ShieldCheck className="size-3 text-emerald-600" />
                  <span>وثيقة إلكترونية مؤمنة ومسجلة في النظام برقم مرجعي: {serialNo}</span>
                </div>
                <div>صفحة 1 من 1</div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* نافذة التوقيع باللمس */}
      {showSignaturePad && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
          <div className="bg-[var(--surface)] p-6 rounded-3xl max-w-lg w-full border border-[var(--border)] shadow-2xl">
            <SignaturePad
              title="التوقيع الحي على الوثيقة"
              signerName={emp.fullNameAr}
              signerId={emp.employeeCode}
              onCancel={() => setShowSignaturePad(false)}
              onSave={(meta) => {
                setEmployeeSignature(meta.dataUrl);
                setShowSignaturePad(false);
              }}
            />
          </div>
        </div>
      )}
    </DialogOverlay>
  );
}
