import { AppProviders } from '@/app/[locale]/app-providers';
import { envConfigs } from '@/config';
import { BrandLogo } from '@/shared/blocks/common/brand-logo';
import { LocaleSelector } from '@/shared/blocks/common/locale-selector';
import { ThemeToggler } from '@/shared/blocks/common/theme-toggler';

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <AppProviders>
      <div className="flex h-screen w-screen items-center justify-center">
        <div className="absolute top-4 left-4">
          <BrandLogo
            brand={{
              title: envConfigs.app_name,
              logo: {
                src: envConfigs.app_logo,
                alt: envConfigs.app_name,
              },
              url: '/',
              target: '_self',
              className: '',
            }}
          />
        </div>
        <div className="absolute top-4 right-4 flex items-center gap-4">
          <ThemeToggler />
          <LocaleSelector type="button" />
        </div>
        <div className="w-full px-4">{children}</div>
      </div>
    </AppProviders>
  );
}
