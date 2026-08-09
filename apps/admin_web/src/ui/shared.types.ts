import type { ReactNode } from 'react';
import type { LucideIcon } from 'lucide-react';

export interface DataTableColumn<T> {
  key: string;
  header: string;
  sortable?: boolean;
  render?: (row: T) => ReactNode;
  className?: string;
  width?: string;
}

export interface PaginationProps {
  page: number;
  pageSize: number;
  total: number;
  onPageChange: (page: number) => void;
}

export interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export interface TabItem {
  key: string;
  label: string;
  icon?: LucideIcon;
  badge?: number;
}

export interface DropdownItem {
  key: string;
  label: string;
  icon?: LucideIcon;
  danger?: boolean;
  onClick: () => void;
}
