import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { SignaturePad, SignaturePadDialog } from '../SignaturePad';

describe('SignaturePad', () => {
  it('renders title, description and signer info', () => {
    render(
      <SignaturePad
        signerName="أحمد علي"
        signerId="EMP-100"
        title="توقيع استلام العهدة"
        description="برجاء التوقيع لتأكيد الاستلام"
      />,
    );

    expect(screen.getByText('توقيع استلام العهدة')).toBeInTheDocument();
    expect(screen.getByText('برجاء التوقيع لتأكيد الاستلام')).toBeInTheDocument();
    expect(screen.getByText('أحمد علي')).toBeInTheDocument();
    expect(screen.getByText('(EMP-100)')).toBeInTheDocument();
  });

  it('renders action buttons with disabled state when canvas is empty', () => {
    render(<SignaturePad signerName="سارة محمد" />);
    const confirmBtn = screen.getByRole('button', { name: /اعتماد التوقيع/i });
    expect(confirmBtn).toBeDisabled();
    const clearBtn = screen.getByRole('button', { name: /مسح وإعادة/i });
    expect(clearBtn).toBeDisabled();
  });

  it('renders Dialog variant when isOpen is true', () => {
    render(
      <SignaturePadDialog
        isOpen={true}
        onClose={() => {}}
        onConfirm={() => {}}
        signerName="محمود حسن"
        title="توقيع القرار الإداري"
      />,
    );

    expect(screen.getAllByText('توقيع القرار الإداري')[0]).toBeInTheDocument();
    expect(screen.getByText('محمود حسن')).toBeInTheDocument();
  });

  it('does not render Dialog variant when isOpen is false', () => {
    render(
      <SignaturePadDialog
        isOpen={false}
        onClose={() => {}}
        onConfirm={() => {}}
        signerName="محمود حسن"
      />,
    );

    expect(screen.queryByText('محمود حسن')).not.toBeInTheDocument();
  });
});
