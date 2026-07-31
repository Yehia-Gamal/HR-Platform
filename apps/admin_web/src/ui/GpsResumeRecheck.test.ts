// V23 §10.4: GPS يعاد فحصه عند الرجوع — source inspection.
// يتحقق من أن جميع صفحات GPS الحساسة تنفذ WidgetsBindingObserver
// وتعيد فحص GPS عند AppLifecycleState.resumed.
import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

const mobilePages = path.resolve(__dirname, '../../../../apps/mobile_flutter/lib/features/mobile_pages');
const coreWidgets = path.resolve(__dirname, '../../../../apps/mobile_flutter/lib/core/widgets');

// الصفحات التي يجب أن تعيد فحص GPS عند الرجوع
const GPS_PAGES = [
  { file: 'mobile_attendance_page.dart', dir: mobilePages },
  { file: 'location_requests_page.dart', dir: mobilePages },
  { file: 'location_incoming_overlay.dart', dir: mobilePages },
  { file: 'live_tracking_session_page.dart', dir: mobilePages },
  { file: 'gps_preflight_banner.dart', dir: coreWidgets },
];

describe('V23 §10.4: GPS يعاد فحصه عند الرجوع', () => {
  for (const page of GPS_PAGES) {
    const filePath = path.join(page.dir, page.file);
    const exists = fs.existsSync(filePath);
    const source = exists ? fs.readFileSync(filePath, 'utf-8') : '';

    describe(page.file, () => {
      it('الملف موجود', () => {
        expect(exists).toBe(true);
      });

      it('ينفّذ WidgetsBindingObserver', () => {
        expect(source).toContain('WidgetsBindingObserver');
      });

      it('يعالج didChangeAppLifecycleState', () => {
        expect(source).toContain('didChangeAppLifecycleState');
      });

      it('يفحص AppLifecycleState.resumed', () => {
        expect(source).toContain('AppLifecycleState.resumed');
      });

      it('يعيد فحص GPS أو يبطل المزوّد', () => {
        // إما _recheckAndRetry أو invalidate (للـ banner)
        const hasRecheck = source.includes('_recheckAndRetry') || source.includes('invalidate');
        expect(hasRecheck).toBe(true);
      });
    });
  }

  it('جميع الصفحات تسجّل المراقب (addObserver) وتلغيه (removeObserver)', () => {
    for (const page of GPS_PAGES) {
      const source = fs.readFileSync(path.join(page.dir, page.file), 'utf-8');
      expect(source).toContain('addObserver');
      expect(source).toContain('removeObserver');
    }
  });
});
