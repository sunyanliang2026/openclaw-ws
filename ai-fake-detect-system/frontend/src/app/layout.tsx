import '@/config/style/global.css';

import { JetBrains_Mono, Merriweather, Noto_Sans_Mono } from 'next/font/google';
import { getLocale, setRequestLocale } from 'next-intl/server';

import { ThemeProvider } from '@/core/theme/provider';
import { Toaster } from '@/shared/components/ui/sonner';

const notoSansMono = Noto_Sans_Mono({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
  preload: true,
});

const merriweather = Merriweather({
  subsets: ['latin'],
  weight: ['400', '700'],
  variable: '--font-serif',
  display: 'swap',
  preload: true,
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
  display: 'swap',
  preload: true,
});

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const locale = await getLocale();
  setRequestLocale(locale);

  return (
    <html
      lang={locale}
      className={`${notoSansMono.variable} ${merriweather.variable} ${jetbrainsMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        <link rel="icon" href="/favicon.ico" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      </head>
      <body suppressHydrationWarning className="overflow-x-hidden">
        <ThemeProvider>{children}</ThemeProvider>
        <Toaster position="top-center" richColors />
      </body>
    </html>
  );
}
