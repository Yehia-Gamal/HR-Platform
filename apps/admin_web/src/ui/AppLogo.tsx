interface AppLogoProps {
  compact?: boolean;
  inverse?: boolean;
}

export function AppLogo({ compact = false, inverse = false }: AppLogoProps) {
  return (
    <div className={`app-logo ${inverse ? 'is-inverse' : ''}`}>
      <span className="brand-mark">
        <img src={inverse ? '/brand/association-logo-white.png' : '/brand/association-logo-blue.png'} alt="شعار جمعية خواطر أحلى شباب" width="64" height="64" />
      </span>
      {!compact ? (
        <div className="min-w-0">
          <p className="brand-name">جمعية خواطر أحلى شباب</p>
          <p className="brand-subtitle">منظومة الإدارة المؤسسية</p>
        </div>
      ) : null}
    </div>
  );
}
