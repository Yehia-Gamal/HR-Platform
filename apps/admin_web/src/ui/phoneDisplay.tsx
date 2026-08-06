// تنسيق أرقام الهواتف الدولية (E.164) بصيغة صحيحة للعرض العربي.
import type { ReactNode } from 'react';

const LOCAL_MARKERS = /[\u200E\u200F\u202A-\u202E\u061C]/g;

/**
 * يعيد ترتيب رقم دولي يبدأ بـ «+» بعد أن أفسدته خوارزمية bidi عند كتابته
 * داخل نص عربي بدون عزل (يظهر كأنه «201099505229+»).
 * الأرقام المحلية (01099505229) أو أي قيمة أخرى تُعاد كما هي.
 */
export function fixIntlPhoneOrder(value: string): string {
  const cleaned = value.replace(LOCAL_MARKERS, '').trim();
  const match = /^(\d+)\+(.*)$/.exec(cleaned);
  if (match) return `+${match[1]}${match[2]}`;
  return cleaned;
}

/** يقصّ أول رقم دولي (مثل +201099505229) من نص ويعيده مفصولاً عن الباقي. */
export function splitIntlPhone(value: string): { phone: string; rest: string } | null {
  const cleaned = value.replace(LOCAL_MARKERS, '');
  const match = /\+\d[\d ]{6,}/.exec(cleaned);
  if (!match) return null;
  const phone = match[0].replace(/[\s\u00A0]+/g, '');
  const rest = `${cleaned.slice(0, match.index)} ${cleaned.slice(match.index + match[0].length)}`.replace(/\s{2,}/g, ' ').trim();
  return { phone, rest };
}

/**
 * يصحّح اتجاه أي رقم دولي داخل نص عربي: يلتقط الرقم، يصلّح ترتيبه إن لزم،
 * ويعرضه في <bdi dir="ltr"> ليبقى «+20…» بشكل صحيح داخل الفقرة.
 */
export function renderSafeIntlPhoneText(value: string): ReactNode {
  const match = splitIntlPhone(value);
  if (!match) return value;
  return (
    <>
      {match.rest ? `${match.rest} ` : ''}
      <bdi dir="ltr">{fixIntlPhoneOrder(match.phone)}</bdi>
    </>
  );
}
