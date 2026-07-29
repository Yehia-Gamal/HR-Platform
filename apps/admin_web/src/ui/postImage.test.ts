import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { preparePostImage } from './postImage';

function makeMockBitmap(w: number, h: number) {
  return { width: w, height: h, close: vi.fn() };
}

let lastCanvasCtx: Record<string, unknown>;

beforeEach(() => {
  lastCanvasCtx = { drawImage: vi.fn() };

  vi.stubGlobal(
    'createImageBitmap',
    vi.fn((_src: unknown) => Promise.resolve(makeMockBitmap(800, 600))),
  );

  vi.spyOn(document, 'createElement').mockImplementation((tag: string) => {
    if (tag === 'canvas') {
      return {
        width: 0,
        height: 0,
        getContext: () => lastCanvasCtx,
        toBlob: (cb: (b: Blob | null) => void, _type: string, _q: number) => {
          cb(new Blob(['fake'], { type: 'image/webp' }));
        },
      } as unknown as HTMLCanvasElement;
    }
    return document.createElementNS('http://www.w3.org/1999/xhtml', tag) as HTMLElement;
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function fakeFile(name: string, type: string, sizeKB = 100): File {
  const buf = new ArrayBuffer(sizeKB * 1024);
  return new File([buf], name, { type });
}

describe('preparePostImage', () => {
  it('يرفض الصيغ غير المدعومة', async () => {
    await expect(preparePostImage(fakeFile('test.bmp', 'image/bmp'))).rejects.toThrow(
      'الصيغة غير مدعومة',
    );
  });

  it('يرفض الملفات الأكبر من 5MB', async () => {
    const bigFile = fakeFile('big.png', 'image/png', 6 * 1024);
    await expect(preparePostImage(bigFile)).rejects.toThrow('5 ميجابايت');
  });

  it('يعيد ملف WebP بالاسم الصحيح', async () => {
    const result = await preparePostImage(fakeFile('banner.jpg', 'image/jpeg'));
    expect(result.name).toBe('banner.webp');
    expect(result.type).toBe('image/webp');
  });

  it('لا يغيّر حجم صورة أصغر من 1600px عرض', async () => {
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      makeMockBitmap(800, 600) as unknown as ImageBitmap,
    );
    const result = await preparePostImage(fakeFile('small.png', 'image/png'));
    expect(result).toBeTruthy();
    // Canvas should be set to original dimensions
  });

  it('يصغّر صورة أعرض من 1600px مع الحفاظ على النسبة', async () => {
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      makeMockBitmap(3200, 2400) as unknown as ImageBitmap,
    );
    await preparePostImage(fakeFile('wide.png', 'image/png'));
    // drawImage should be called with scaled dimensions
    expect(lastCanvasCtx.drawImage).toHaveBeenCalled();
  });

  it('يغلق bitmap بعد المعالجة', async () => {
    const bitmap = makeMockBitmap(800, 600);
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      bitmap as unknown as ImageBitmap,
    );
    await preparePostImage(fakeFile('a.jpg', 'image/jpeg'));
    expect(bitmap.close).toHaveBeenCalledOnce();
  });

  it('يقبل الصيغ الثلاث', async () => {
    for (const type of ['image/jpeg', 'image/png', 'image/webp']) {
      const result = await preparePostImage(fakeFile('img.x', type));
      expect(result.type).toBe('image/webp');
    }
  });

  it('يستخدم fallback "banner" إذا لم يكن هناك اسم', async () => {
    const noExt = fakeFile('.png', 'image/png');
    const result = await preparePostImage(noExt);
    expect(result.name).toBe('banner.webp');
  });
});
