/**
 * التقاط وتصدير بطاقة التقرير التنفيذي كصورة PNG عالية الدقة (2x).
 */
export async function captureExecutiveCardCanvas(el: HTMLElement): Promise<HTMLCanvasElement> {
  const h2cModule = await import('html2canvas-pro');
  const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as unknown as typeof h2cModule.default);

  const images = Array.from(el.querySelectorAll('img'));
  await Promise.all(
    images.map((img) => {
      if (img.complete) return Promise.resolve();
      return new Promise((resolve) => {
        img.onload = () => resolve(true);
        img.onerror = () => resolve(true);
      });
    }),
  );
  if (document.fonts) {
    try {
      await document.fonts.ready;
    } catch {
      // ignore
    }
  }

  const TARGET_WIDTH = 1040;
  const fullWidth = TARGET_WIDTH;
  const fullHeight = Math.max(el.scrollHeight, el.offsetHeight);

  const scrollParent = el.parentElement;
  const prevScrollTop = scrollParent ? scrollParent.scrollTop : 0;
  if (scrollParent) scrollParent.scrollTop = 0;

  try {
    return await html2canvas(el, {
      scale: 2,
      useCORS: true,
      allowTaint: false,
      logging: false,
      backgroundColor: '#0b1329',
      width: fullWidth,
      height: fullHeight,
      windowWidth: fullWidth,
      windowHeight: fullHeight,
      x: 0,
      y: 0,
      scrollX: 0,
      scrollY: 0,
      onclone: (clonedDoc: Document, clonedEl: HTMLElement) => {
        clonedEl.style.width = `${TARGET_WIDTH}px`;
        clonedEl.style.minWidth = `${TARGET_WIDTH}px`;
        clonedEl.style.maxWidth = `${TARGET_WIDTH}px`;
        clonedEl.style.boxSizing = 'border-box';
        clonedEl.style.height = `${fullHeight}px`;
        clonedEl.style.minHeight = `${fullHeight}px`;
        clonedEl.style.maxHeight = 'none';
        clonedEl.style.overflow = 'visible';
        clonedEl.style.position = 'static';
        clonedEl.style.transform = 'none';

        // تأمين تقييد أبعاد الشعار الرسمي بدقة داخل الكائن المستنسخ لمنع تمدد صورته الأصلية
        const clonedImgs = clonedEl.querySelectorAll('img');
        clonedImgs.forEach((img) => {
          img.style.width = '80px';
          img.style.height = '80px';
          img.style.minWidth = '80px';
          img.style.minHeight = '80px';
          img.style.maxWidth = '80px';
          img.style.maxHeight = '80px';
          img.style.objectFit = 'contain';
          img.style.display = 'block';
          img.setAttribute('width', '80');
          img.setAttribute('height', '80');
        });

        let curr: HTMLElement | null = clonedEl.parentElement;
        while (curr && curr !== clonedDoc.body) {
          curr.style.width = `${TARGET_WIDTH}px`;
          curr.style.minWidth = `${TARGET_WIDTH}px`;
          curr.style.maxWidth = 'none';
          curr.style.height = 'auto';
          curr.style.minHeight = 'auto';
          curr.style.maxHeight = 'none';
          curr.style.overflow = 'visible';
          curr.style.display = 'block';
          curr.style.transform = 'none';
          curr = curr.parentElement;
        }

        if (clonedDoc.body) {
          clonedDoc.body.style.width = `${TARGET_WIDTH}px`;
          clonedDoc.body.style.minWidth = `${TARGET_WIDTH}px`;
          clonedDoc.body.style.maxWidth = 'none';
          clonedDoc.body.style.height = 'auto';
          clonedDoc.body.style.minHeight = 'auto';
          clonedDoc.body.style.maxHeight = 'none';
          clonedDoc.body.style.overflow = 'visible';
        }
      },
    });
  } finally {
    if (scrollParent) scrollParent.scrollTop = prevScrollTop;
  }
}

export function triggerPngDownload(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
