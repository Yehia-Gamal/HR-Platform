import { useSearchParams } from 'react-router';

/**
 * حالة فلتر مرتبطة بعنوان الصفحة — تبقى الفلاتر محفوظة عند التحديث
 * والمشاركة، وتُحذف من الرابط تلقائياً عند العودة للقيمة الافتراضية.
 */
export function useUrlState(key: string, initial: string) {
  const [searchParams, setSearchParams] = useSearchParams();
  const value = searchParams.get(key) ?? initial;
  const setValue = (next: string) => {
    const params = new URLSearchParams(searchParams);
    if (next === initial) {
      params.delete(key);
    } else {
      params.set(key, next);
    }
    setSearchParams(params, { replace: true });
  };
  return [value, setValue] as const;
}
