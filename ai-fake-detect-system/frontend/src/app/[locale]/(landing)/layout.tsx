import { ReactNode } from 'react';

import { AppProviders } from '@/app/[locale]/app-providers';

export default function LandingLayout({
  children,
}: {
  children: ReactNode;
}) {
  return <AppProviders>{children}</AppProviders>;
}
