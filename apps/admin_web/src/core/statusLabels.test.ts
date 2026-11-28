import { describe, expect, it } from 'vitest';
import { translateStatus, translateSystemMessage } from './statusLabels';

describe('statusLabels', () => {
  it('يترجم حالات التوظيف المختلفة للعربية', () => {
    expect(translateStatus('active')).toBe('نشط');
    expect(translateStatus('hired')).toBe('تم التعيين');
    expect(translateStatus('rejected')).toBe('مرفوض');
    expect(translateStatus('withdrawn')).toBe('منسحب');
    expect(translateStatus('posted')).toBe('منشور');
  });

  it('يترجم مراحل التقييم سواء بشرطة سفلية أو بمسافة أو أحرف كبيرة', () => {
    expect(translateStatus('manager_review')).toBe('عند المدير المباشر');
    expect(translateStatus('manager review')).toBe('عند المدير المباشر');
    expect(translateStatus('MANAGER_REVIEW')).toBe('عند المدير المباشر');
    expect(translateStatus('hr_review')).toBe('مراجعة الموارد البشرية');
  });

  it('يترجم حالات النظام والنسخ الاحتياطي والبيئات', () => {
    expect(translateStatus('completed')).toBe('مكتمل');
    expect(translateStatus('push')).toBe('إشعار فوري');
    expect(translateStatus('edge')).toBe('الدوال الخادمية');
  });

  it('يعرّب مصطلحات الإشعار الإنجليزية في رسائل النظام', () => {
    expect(translateSystemMessage('تأخر مؤقت في تسليم إشعار Push')).toBe('تأخر مؤقت في تسليم إشعار فوري');
  });
});
