import { ReactNode } from 'react';

import { ThemeProvider } from '@/core/theme/provider';
import { LocaleDetector } from '@/shared/blocks/common';

export default function LandingLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <ThemeProvider>
      <LocaleDetector />
      {children}
    </ThemeProvider>
  );
}
