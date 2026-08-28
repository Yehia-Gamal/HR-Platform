import { Data } from './EmployeeDetailShared';

interface Props {
  label: string;
  value: string | null;
}

export function EmployeeDataItem({ label, value }: Props) {
  return <Data label={label} value={value} />;
}