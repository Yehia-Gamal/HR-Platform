import { useState } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useCreateAssociationProject } from './useAssociationProjects';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import { useEmployees } from '../employees/useEmployees';

interface Props {
  onClose: () => void;
}

export function ProjectCreateDialog({ onClose }: Props) {
  const create = useCreateAssociationProject();
  const { data: org } = useOrganizationLookups();
  const { data: employees = [] } = useEmployees();

  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');
  const [deptId, setDeptId] = useState('');
  const [ownerId, setOwnerId] = useState('');
  const [priority, setPriority] = useState('medium');
  const [start, setStart] = useState('');
  const [end, setEnd] = useState('');

  async function submit() {
    await create.mutateAsync({
      code, name, description: desc, departmentId: deptId,
      ownerEmployeeId: ownerId, priority, startDate: start, targetEndDate: end,
    });
    onClose();
  }

  return (
    <DialogOverlay title="إنشاء مشروع جديد" onClose={onClose}>
      <div className="space-y-4 p-4">
        <div className="grid grid-cols-2 gap-4">
          <label className="block">
            <span className="text-sm font-medium">كود المشروع *</span>
            <input className="input mt-1 w-full" placeholder="PRJ-001" value={code} onChange={(e) => setCode(e.target.value)} />
          </label>
          <label className="block">
            <span className="text-sm font-medium">اسم المشروع *</span>
            <input className="input mt-1 w-full" value={name} onChange={(e) => setName(e.target.value)} />
          </label>
        </div>
        <label className="block">
          <span className="text-sm font-medium">الوصف</span>
          <textarea className="input mt-1 w-full" rows={2} value={desc} onChange={(e) => setDesc(e.target.value)} />
        </label>
        <div className="grid grid-cols-2 gap-4">
          <label className="block">
            <span className="text-sm font-medium">الإدارة *</span>
            <select className="input mt-1 w-full" value={deptId} onChange={(e) => setDeptId(e.target.value)}>
              <option value="">— اختر —</option>
              {org?.departments.map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
            </select>
          </label>
          <label className="block">
            <span className="text-sm font-medium">المسؤول *</span>
            <select className="input mt-1 w-full" value={ownerId} onChange={(e) => setOwnerId(e.target.value)}>
              <option value="">— اختر —</option>
              {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.fullNameAr}</option>)}
            </select>
          </label>
        </div>
        <div className="grid grid-cols-3 gap-4">
          <label className="block">
            <span className="text-sm font-medium">الأولوية</span>
            <select className="input mt-1 w-full" value={priority} onChange={(e) => setPriority(e.target.value)}>
              <option value="low">منخفضة</option>
              <option value="medium">متوسطة</option>
              <option value="high">عالية</option>
              <option value="critical">حرجة</option>
            </select>
          </label>
          <label className="block">
            <span className="text-sm font-medium">تاريخ البدء</span>
            <input type="date" className="input mt-1 w-full" value={start} onChange={(e) => setStart(e.target.value)} />
          </label>
          <label className="block">
            <span className="text-sm font-medium">الموعد النهائي</span>
            <input type="date" className="input mt-1 w-full" value={end} onChange={(e) => setEnd(e.target.value)} />
          </label>
        </div>
        <button
          onClick={submit}
          disabled={!code.trim() || !name.trim() || !deptId || !ownerId || create.isPending}
          className="btn-primary w-full"
        >
          {create.isPending ? 'جاري الإنشاء...' : 'إنشاء المشروع'}
        </button>
      </div>
    </DialogOverlay>
  );
}
