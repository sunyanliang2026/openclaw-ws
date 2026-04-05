'use client';

import { ReactNode } from 'react';

import { ThemeProvider } from '@/core/theme/provider';
import { Toaster } from '@/shared/components/ui/sonner';
import { AppContextProvider } from '@/shared/contexts/app';

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider>
      <AppContextProvider>
        {children}
        <Toaster position="top-center" richColors />
      </AppContextProvider>
    </ThemeProvider>
  );
}
