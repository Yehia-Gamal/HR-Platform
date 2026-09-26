import type { ProjectLedStatus } from '@ahla/shared-contracts';
import { LED_META } from './projectLedStatus';

/** لمبة حالة المشروع — لون + وميض عند «يحتاج تدخل». */
export function ProjectLed({ status, large = false }: { status: ProjectLedStatus; large?: boolean }) {
  const meta = LED_META[status];
  return (
    <span className={`project-led project-led--${status}${large ? ' is-lg' : ''}`} role="img" aria-label={`حالة المشروع: ${meta.label}`} title={meta.hint} />
  );
}
