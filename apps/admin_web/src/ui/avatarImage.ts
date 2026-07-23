const MAX_AVATAR_BYTES = 5 * 1024 * 1024;
const MIN_AVATAR_EDGE = 512;
const OUTPUT_EDGE = 1024;

export async function prepareAvatarFile(file: File): Promise<File> {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
    throw new Error('الصيغة غير مدعومة. استخدم JPG أو PNG أو WEBP.');
  }
  if (file.size > MAX_AVATAR_BYTES) {
    throw new Error('حجم الصورة أكبر من 5 ميجابايت.');
  }

  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  try {
    if (Math.min(bitmap.width, bitmap.height) < MIN_AVATAR_EDGE) {
      throw new Error('دقة الصورة منخفضة. استخدم صورة لا تقل عن 512×512 بكسل.');
    }

    const sourceEdge = Math.min(bitmap.width, bitmap.height);
    const sourceX = Math.round((bitmap.width - sourceEdge) / 2);
    const sourceY = Math.round((bitmap.height - sourceEdge) / 2);
    const outputEdge = Math.min(OUTPUT_EDGE, sourceEdge);
    const canvas = document.createElement('canvas');
    canvas.width = outputEdge;
    canvas.height = outputEdge;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('تعذر تجهيز الصورة في هذا المتصفح.');
    context.drawImage(bitmap, sourceX, sourceY, sourceEdge, sourceEdge, 0, 0, outputEdge, outputEdge);

    const blob = await new Promise<Blob>((resolve, reject) => {
      canvas.toBlob((value) => value ? resolve(value) : reject(new Error('تعذر ضغط الصورة.')), 'image/webp', 0.86);
    });
    const stem = file.name.replace(/\.[^.]+$/, '') || 'avatar';
    return new File([blob], `${stem}.webp`, { type: 'image/webp', lastModified: Date.now() });
  } finally {
    bitmap.close();
  }
}
