import { render, screen, fireEvent } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { OfficialDocumentGeneratorModal } from '../OfficialDocumentGeneratorModal';
import * as whatsappShare from '../../../core/whatsappShare';

vi.mock('../../../core/whatsappShare', () => ({
  shareOfficialDocumentNotice: vi.fn(),
}));

describe('OfficialDocumentGeneratorModal', () => {
  it('renders official document generator and switches to mission assignment with QR verification', () => {
    render(
      <OfficialDocumentGeneratorModal
        isOpen={true}
        onClose={vi.fn()}
      />
    );

    // Initial default is salary certificate
    expect(screen.getByText('شهادة تعريف بالراتب (HR Letter)')).toBeDefined();

    // Click mission assignment button
    const missionBtn = screen.getByText(/خطاب تكليف بمأمورية وقافلة ميدانية/);
    fireEvent.click(missionBtn);

    // Form inputs for mission should appear
    expect(screen.getByText('مسمى المأمورية / القافلة')).toBeDefined();
    expect(screen.getByText('نطاق الوجهة والمحافظة')).toBeDefined();

    // Printable A4 sheet should show title and Smart QR verification
    expect(screen.getByText('خــطــاب تــكــلــيـف بـمـأمـوريـة وقـافـلـة مـيـدانـيـة')).toBeDefined();
    expect(screen.getByText(/رمز التحقق الذكي المعتمد/)).toBeDefined();
    expect(screen.getByText(/SECURED DOCUMENT/)).toBeDefined();
  });

  it('triggers whatsapp share notice with proper parameters', () => {
    const shareSpy = vi.spyOn(whatsappShare, 'shareOfficialDocumentNotice');

    render(
      <OfficialDocumentGeneratorModal
        isOpen={true}
        onClose={vi.fn()}
        initialType="mission_assignment"
      />
    );

    const shareBtn = screen.getByText('مشاركة إشعار الوثيقة (WhatsApp)');
    fireEvent.click(shareBtn);

    expect(shareSpy).toHaveBeenCalledTimes(1);
    expect(shareSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        docTitle: expect.stringContaining('خطاب تكليف بمأمورية'),
      })
    );
  });
});
