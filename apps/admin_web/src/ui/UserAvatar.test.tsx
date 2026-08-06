import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { avatarInitial, UserAvatar } from './UserAvatar';

describe('UserAvatar', () => {
  it('uses a safe fallback for empty and Arabic names', () => {
    expect(avatarInitial('')).toBe('؟');
    expect(avatarInitial('  أحمد محمد')).toBe('أ');
  });

  it('falls back to the initial when the remote image fails', () => {
    render(<UserAvatar displayName="أحمد" photoUrl="https://example.com/missing.jpg" />);
    fireEvent.error(document.querySelector('img') as HTMLImageElement);
    expect(screen.getByText('أ')).toBeTruthy();
    expect(screen.getByRole('img', { name: 'الصورة الشخصية: أحمد' })).toBeTruthy();
  });
});
