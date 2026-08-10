import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { prepareAvatarFile } from './avatarImage';

// --- Mocks for Canvas / ImageBitmap ---
function makeMockBitmap(w: number, h: number) {
  return { width: w, height: h, close: vi.fn() };
}

let lastCanvasCtx: Record<string, unknown>;

beforeEach(() => {
  lastCanvasCtx = { drawImage: vi.fn() };

  vi.stubGlobal(
    'createImageBitmap',
    vi.fn((src: unknown) => { void src; return Promise.resolve(makeMockBitmap(1024, 1024)); }),
  );

  vi.spyOn(document, 'createElement').mockImplementation((tag: string) => {
    if (tag === 'canvas') {
      return {
        width: 0,
        height: 0,
        getContext: () => lastCanvasCtx,
        toBlob: (cb: (b: Blob | null) => void, type: string, q: number) => {
          void type;
          void q;
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

describe('prepareAvatarFile', () => {
  it('يرفض الصيغ غير المدعومة', async () => {
    await expect(prepareAvatarFile(fakeFile('test.gif', 'image/gif'))).rejects.toThrow(
      'الصيغة غير مدعومة',
    );
  });

  it('يرفض الملفات الأكبر من 5MB', async () => {
    const bigFile = fakeFile('big.png', 'image/png', 6 * 1024);
    await expect(prepareAvatarFile(bigFile)).rejects.toThrow('5 ميجابايت');
  });

  it('يرفض الصور الأصغر من 512px', async () => {
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      makeMockBitmap(256, 256) as unknown as ImageBitmap,
    );
    await expect(prepareAvatarFile(fakeFile('small.png', 'image/png'))).rejects.toThrow(
      '512×512',
    );
  });

  it('يعيد ملف WebP بالاسم الصحيح', async () => {
    const result = await prepareAvatarFile(fakeFile('photo.jpg', 'image/jpeg'));
    expect(result.name).toBe('photo.webp');
    expect(result.type).toBe('image/webp');
  });

  it('يقبل PNG و WEBP', async () => {
    const png = await prepareAvatarFile(fakeFile('a.png', 'image/png'));
    expect(png.type).toBe('image/webp');

    const webp = await prepareAvatarFile(fakeFile('b.webp', 'image/webp'));
    expect(webp.type).toBe('image/webp');
  });

  it('يغلق bitmap بعد المعالجة', async () => {
    const bitmap = makeMockBitmap(1024, 1024);
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      bitmap as unknown as ImageBitmap,
    );
    await prepareAvatarFile(fakeFile('a.jpg', 'image/jpeg'));
    expect(bitmap.close).toHaveBeenCalledOnce();
  });

  it('يغلق bitmap حتى عند حدوث خطأ', async () => {
    const bitmap = makeMockBitmap(100, 100); // too small → will throw
    vi.mocked(globalThis.createImageBitmap).mockResolvedValueOnce(
      bitmap as unknown as ImageBitmap,
    );
    await expect(prepareAvatarFile(fakeFile('a.jpg', 'image/jpeg'))).rejects.toThrow();
    expect(bitmap.close).toHaveBeenCalledOnce();
  });

  it('يستخدم fallback "avatar" إذا لم يكن هناك اسم', async () => {
    const noExt = fakeFile('.jpg', 'image/jpeg');
    const result = await prepareAvatarFile(noExt);
    expect(result.name).toBe('avatar.webp');
  });
});
