import { UserRound } from 'lucide-react';
import { useEffect, useState } from 'react';

type AvatarSize = 'sm' | 'md' | 'lg';

export function avatarInitial(displayName: string) {
  return Array.from(displayName.trim())[0] ?? '؟';
}

export function UserAvatar({
  displayName,
  photoUrl,
  size = 'md',
  eager = false,
  announceName = true,
  className = '',
}: {
  displayName: string;
  photoUrl?: string | null;
  size?: AvatarSize;
  eager?: boolean;
  announceName?: boolean;
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    setFailed(false);
    setLoaded(false);
  }, [photoUrl]);

  const canShowImage = Boolean(photoUrl && !failed);
  return (
    <span
      className={`user-avatar ${size === 'sm' ? 'small' : size === 'lg' ? 'large' : ''} ${canShowImage && !loaded ? 'is-loading' : ''} ${className}`.trim()}
      role={announceName ? 'img' : undefined}
      aria-label={announceName ? `الصورة الشخصية: ${displayName}` : undefined}
    >
      {canShowImage ? (
        <img
          src={photoUrl!}
          alt=""
          loading={eager ? 'eager' : 'lazy'}
          decoding="async"
          onLoad={() => setLoaded(true)}
          onError={() => setFailed(true)}
        />
      ) : displayName.trim() ? (
        <span aria-hidden="true">{avatarInitial(displayName)}</span>
      ) : (
        <UserRound aria-hidden="true" />
      )}
    </span>
  );
}
