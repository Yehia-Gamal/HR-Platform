const MAX_POST_BYTES = 5 * 1024 * 1024;
const MAX_OUTPUT_WIDTH = 1600;

/**
 * Validate, resize and convert a post/banner image to WebP.
 * Unlike avatars this preserves the original aspect ratio — no square crop.
 */
export async function preparePostImage(file: File): Promise<File> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    throw new Error('الصيغة غير مدعومة. استخدم JPG أو PNG أو WEBP.');
  }
  if (file.size > MAX_POST_BYTES) {
    throw new Error('حجم الصورة أكبر من 5 ميجابايت.');
  }

  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  try {
    const scale = bitmap.width > MAX_OUTPUT_WIDTH ? MAX_OUTPUT_WIDTH / bitmap.width : 1;
    const outW = Math.round(bitmap.width * scale);
    const outH = Math.round(bitmap.height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = outW;
    canvas.height = outH;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('تعذر تجهيز الصورة في هذا المتصفح.');
    context.drawImage(bitmap, 0, 0, outW, outH);

    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob((value) => (value ? resolve(value) : reject(new Error('تعذر ضغط الصورة.'))), 'image/webp', 0.86);
    });
    const stem = file.name.replace(/\.[^.]+$/, '') || 'banner';
    return new File([blob], `${stem}.webp`, { type: 'image/webp', lastModified: Date.now() });
  } finally {
    bitmap.close();
  }
}
