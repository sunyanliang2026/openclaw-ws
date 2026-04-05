import { getRequestConfig } from 'next-intl/server';
import { headers } from 'next/headers';

import {
  defaultLocale,
  localeMessagesPaths,
  localeMessagesRootPath,
} from '@/config/locale';

import { routing } from './config';

const COMMON_MESSAGE_PATHS = ['common'] as const;
const ADMIN_MESSAGE_PATHS = localeMessagesPaths.filter((path) =>
  path.startsWith('admin/')
);
const SETTINGS_MESSAGE_PATHS = localeMessagesPaths.filter((path) =>
  path.startsWith('settings/')
);
const ACTIVITY_MESSAGE_PATHS = localeMessagesPaths.filter((path) =>
  path.startsWith('activity/')
);
const AI_MESSAGE_PATHS = localeMessagesPaths.filter((path) =>
  path.startsWith('ai/')
);
const PAGE_MESSAGE_PATHS = localeMessagesPaths.filter((path) =>
  path.startsWith('pages/')
);

function normalizePathname(pathname: string, locale: string) {
  if (!pathname || pathname === '/') {
    return '/';
  }

  if (pathname === `/${locale}`) {
    return '/';
  }

  if (pathname.startsWith(`/${locale}/`)) {
    return pathname.slice(locale.length + 1) || '/';
  }

  return pathname;
}

function dedupeMessagePaths(paths: string[]) {
  return Array.from(new Set(paths));
}

function getMessagePathsForPathname(pathname: string) {
  const normalizedPathname = pathname || '/';

  if (
    normalizedPathname === '/' ||
    normalizedPathname === '/detect' ||
    normalizedPathname === '/result'
  ) {
    return [...COMMON_MESSAGE_PATHS];
  }

  if (
    normalizedPathname === '/sign-in' ||
    normalizedPathname === '/sign-up' ||
    normalizedPathname === '/verify-email'
  ) {
    return [...COMMON_MESSAGE_PATHS];
  }

  if (normalizedPathname.startsWith('/admin')) {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, ...ADMIN_MESSAGE_PATHS]);
  }

  if (normalizedPathname.startsWith('/settings')) {
    return dedupeMessagePaths([
      ...COMMON_MESSAGE_PATHS,
      ...SETTINGS_MESSAGE_PATHS,
    ]);
  }

  if (normalizedPathname.startsWith('/activity')) {
    return dedupeMessagePaths([
      ...COMMON_MESSAGE_PATHS,
      ...ACTIVITY_MESSAGE_PATHS,
    ]);
  }

  if (normalizedPathname.startsWith('/chat')) {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'ai/chat']);
  }

  if (normalizedPathname === '/pricing') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'pages/pricing']);
  }

  if (normalizedPathname === '/showcases') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'pages/showcases']);
  }

  if (normalizedPathname === '/blog' || normalizedPathname.startsWith('/blog/')) {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'pages/blog']);
  }

  if (normalizedPathname === '/updates') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'pages/updates']);
  }

  if (normalizedPathname === '/ai-image-generator') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'ai/image']);
  }

  if (normalizedPathname === '/ai-video-generator') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'ai/video']);
  }

  if (normalizedPathname === '/ai-music-generator') {
    return dedupeMessagePaths([...COMMON_MESSAGE_PATHS, 'ai/music']);
  }

  return dedupeMessagePaths([
    ...COMMON_MESSAGE_PATHS,
    ...AI_MESSAGE_PATHS,
    ...PAGE_MESSAGE_PATHS,
  ]);
}

export async function loadMessages(
  path: string,
  locale: string = defaultLocale
) {
  try {
    // try to load locale messages
    const messages = await import(
      `@/config/locale/messages/${locale}/${path}.json`
    );
    return messages.default;
  } catch {
    try {
      // try to load default locale messages
      const messages = await import(
        `@/config/locale/messages/${defaultLocale}/${path}.json`
      );
      return messages.default;
    } catch {
      // if default locale is not found, return empty object
      return {};
    }
  }
}

export default getRequestConfig(async ({ requestLocale }) => {
  let locale = await requestLocale;
  if (!locale || !routing.locales.includes(locale as string)) {
    locale = routing.defaultLocale;
  }

  if (['zh-CN'].includes(locale)) {
    locale = 'zh';
  }

  try {
    const requestHeaders = await headers();
    const requestPathname = requestHeaders.get('x-pathname') || '/';
    const normalizedPathname = normalizePathname(requestPathname, locale);
    const messagePaths = getMessagePathsForPathname(normalizedPathname);

    // load all local messages
    const allMessages = await Promise.all(
      messagePaths.map((path) => loadMessages(path, locale))
    );

    // merge all local messages
    const messages: Record<string, unknown> = {};

    messagePaths.forEach((path, index) => {
      const localMessages = allMessages[index];

      const keys = path.split('/');
      let current = messages;

      for (let i = 0; i < keys.length - 1; i++) {
        if (!current[keys[i]]) {
          current[keys[i]] = {};
        }
        current = current[keys[i]];
      }

      current[keys[keys.length - 1]] = localMessages;
    });

    return {
      locale,
      messages,
    };
  } catch {
    return {
      locale: defaultLocale,
      messages: await loadMessages(localeMessagesRootPath, defaultLocale),
    };
  }
});
