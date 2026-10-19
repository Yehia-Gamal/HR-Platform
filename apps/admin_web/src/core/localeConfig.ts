/**
 * توحيد النظام الرقمي عالمياً عبر منصة أحلى شباب (اللاتينية: 0123456789)
 *
 * يضمن هذا الملف أن كافة استدعاءات التنسيق الزمني والتواريخ والمبالغ والنسب
 * (سواء عبر Intl.DateTimeFormat أو Intl.NumberFormat أو toLocaleString أو toLocaleDateString)
 * تلتزم بنظام الأرقام اللاتينية 123 مع نصوص عربية سليمة تماماً عبر جميع الواجهات والتقارير.
 */

export const APP_LOCALE = 'ar-EG-u-nu-latn';

export function enforceLatinNumeralsGlobal(): void {
  if (typeof window === 'undefined') return;

  const normalizeLocales = (locales?: unknown): any => {
    if (!locales) return APP_LOCALE;
    if (typeof locales === 'string') {
      if (locales === 'ar' || locales === 'ar-EG' || (locales.startsWith('ar') && !locales.includes('-u-nu-'))) {
        return `${locales}-u-nu-latn`;
      }
      return locales;
    }
    if (Array.isArray(locales)) {
      return locales.map((l) =>
        typeof l === 'string' && (l === 'ar' || l === 'ar-EG' || (l.startsWith('ar') && !l.includes('-u-nu-')))
          ? `${l}-u-nu-latn`
          : l,
      );
    }
    return locales;
  };

  // 1. Intl.DateTimeFormat
  const OriginalDateTimeFormat = Intl.DateTimeFormat;
  const PatchedDateTimeFormat = function (this: unknown, locales?: string | string[], options?: Intl.DateTimeFormatOptions) {
    return new OriginalDateTimeFormat(normalizeLocales(locales), options);
  } as unknown as typeof Intl.DateTimeFormat;
  (PatchedDateTimeFormat as any).prototype = OriginalDateTimeFormat.prototype;
  PatchedDateTimeFormat.supportedLocalesOf = OriginalDateTimeFormat.supportedLocalesOf;
  Intl.DateTimeFormat = PatchedDateTimeFormat;

  // 2. Intl.NumberFormat
  const OriginalNumberFormat = Intl.NumberFormat;
  const PatchedNumberFormat = function (this: unknown, locales?: string | string[], options?: Intl.NumberFormatOptions) {
    return new OriginalNumberFormat(normalizeLocales(locales), options);
  } as unknown as typeof Intl.NumberFormat;
  (PatchedNumberFormat as any).prototype = OriginalNumberFormat.prototype;
  PatchedNumberFormat.supportedLocalesOf = OriginalNumberFormat.supportedLocalesOf;
  Intl.NumberFormat = PatchedNumberFormat;

  // 3. Date.prototype overrides
  const origToLocaleDateString = Date.prototype.toLocaleDateString;
  Date.prototype.toLocaleDateString = function (locales?: Intl.LocalesArgument, options?: Intl.DateTimeFormatOptions) {
    return origToLocaleDateString.call(this, normalizeLocales(locales), options);
  };

  const origToLocaleTimeString = Date.prototype.toLocaleTimeString;
  Date.prototype.toLocaleTimeString = function (locales?: Intl.LocalesArgument, options?: Intl.DateTimeFormatOptions) {
    return origToLocaleTimeString.call(this, normalizeLocales(locales), options);
  };

  const origToLocaleString = Date.prototype.toLocaleString;
  Date.prototype.toLocaleString = function (locales?: Intl.LocalesArgument, options?: Intl.DateTimeFormatOptions) {
    return origToLocaleString.call(this, normalizeLocales(locales), options);
  };

  // 4. Number.prototype override
  const origNumToLocaleString = Number.prototype.toLocaleString;
  Number.prototype.toLocaleString = function (locales?: Intl.LocalesArgument, options?: Intl.NumberFormatOptions) {
    return origNumToLocaleString.call(this, normalizeLocales(locales), options);
  };
}
