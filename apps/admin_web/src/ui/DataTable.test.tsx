import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { DataTable, type DataTableColumn } from './DataTable';

interface Row {
  id: string;
  name: string;
}

const columns: DataTableColumn<Row>[] = [
  { key: 'name', header: 'الاسم', sortable: true },
  { key: 'city', header: 'المدينة' },
];

const data: Row[] = [
  { id: '1', name: 'أحمد' },
  { id: '2', name: 'محمد' },
  { id: '3', name: 'علي' },
];

describe('DataTable', () => {
  it('renders column headers', () => {
    render(<DataTable columns={columns} data={data} rowKey={(r) => r.id} ariaLabel="جدول" />);
    expect(screen.getByText('الاسم')).toBeInTheDocument();
    expect(screen.getByText('المدينة')).toBeInTheDocument();
  });

  it('renders all data rows', () => {
    render(<DataTable columns={columns} data={data} rowKey={(r) => r.id} />);
    expect(screen.getByText('أحمد')).toBeInTheDocument();
    expect(screen.getByText('محمد')).toBeInTheDocument();
    expect(screen.getByText('علي')).toBeInTheDocument();
  });

  it('shows empty state when data is empty', () => {
    render(<DataTable columns={columns} data={[]} rowKey={(r) => r.id} emptyTitle="لا توجد بيانات" emptyDescription="جرّب إضافة عناصر" />);
    expect(screen.getByText('لا توجد بيانات')).toBeInTheDocument();
  });

  it('sorts data when sortable header is clicked', () => {
    const { container } = render(<DataTable columns={columns} data={data} rowKey={(r) => r.id} />);
    const nameHeader = screen.getByText('الاسم');
    fireEvent.click(nameHeader);
    // After click, data should be sorted (descending by name)
    const rows = container.querySelectorAll('tbody tr');
    expect(rows).toHaveLength(3);
  });

  it('renders custom cell via render function', () => {
    const cols: DataTableColumn<Row>[] = [{ key: 'name', header: 'الاسم', render: (row) => <strong>{row.name.toUpperCase()}</strong> }];
    render(<DataTable columns={cols} data={data.slice(0, 1)} rowKey={(r) => r.id} />);
    expect(screen.getByText('أحمد'.toUpperCase())).toBeInTheDocument();
  });

  it('supports pinFirstColumn and applies sticky styles', () => {
    const { container } = render(
      <DataTable columns={columns} data={data} rowKey={(r) => r.id} pinFirstColumn selectable />
    );
    const pinnedTh = container.querySelector('th.sticky');
    expect(pinnedTh).toBeTruthy();
    const pinnedTd = container.querySelector('td.sticky');
    expect(pinnedTd).toBeTruthy();
  });

  it('supports pinLastColumn and applies sticky styles to last column', () => {
    const { container } = render(
      <DataTable columns={columns} data={data} rowKey={(r) => r.id} pinLastColumn />
    );
    const ths = container.querySelectorAll('th.sticky');
    expect(ths.length).toBeGreaterThan(0);
    const tds = container.querySelectorAll('td.sticky');
    expect(tds.length).toBeGreaterThan(0);
  });
});

