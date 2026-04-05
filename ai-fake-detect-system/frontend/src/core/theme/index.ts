import { envConfigs } from '@/config';
import { defaultTheme } from '@/config/theme';
import { Blog } from '@/themes/default/blocks/blog';
import { BlogDetail } from '@/themes/default/blocks/blog-detail';
import { Cta } from '@/themes/default/blocks/cta';
import { Faq } from '@/themes/default/blocks/faq';
import { FeaturesAccordion } from '@/themes/default/blocks/features-accordion';
import { FeaturesFlow } from '@/themes/default/blocks/features-flow';
import { FeaturesList } from '@/themes/default/blocks/features-list';
import { FeaturesMedia } from '@/themes/default/blocks/features-media';
import { FeaturesStep } from '@/themes/default/blocks/features-step';
import { Features } from '@/themes/default/blocks/features';
import { Footer } from '@/themes/default/blocks/footer';
import { Header } from '@/themes/default/blocks/header';
import { Hero } from '@/themes/default/blocks/hero';
import { Logos } from '@/themes/default/blocks/logos';
import { PageDetail } from '@/themes/default/blocks/page-detail';
import { Pricing } from '@/themes/default/blocks/pricing';
import { ShowcasesFlow } from '@/themes/default/blocks/showcases-flow';
import { Showcases } from '@/themes/default/blocks/showcases';
import { SocialAvatars } from '@/themes/default/blocks/social-avatars';
import { Stats } from '@/themes/default/blocks/stats';
import { Subscribe } from '@/themes/default/blocks/subscribe';
import { Testimonials } from '@/themes/default/blocks/testimonials';
import { Updates } from '@/themes/default/blocks/updates';
import DefaultLandingLayout from '@/themes/default/layouts/landing';
import DefaultDynamicPage from '@/themes/default/pages/dynamic-page';
import DefaultStaticPage from '@/themes/default/pages/static-page';

type ThemeComponent = React.ComponentType<unknown>;

const themePages: Record<string, Record<string, ThemeComponent>> = {
  default: {
    'dynamic-page': DefaultDynamicPage,
    'static-page': DefaultStaticPage,
  },
};

const themeLayouts: Record<string, Record<string, ThemeComponent>> = {
  default: {
    landing: DefaultLandingLayout,
  },
};

const themeBlocks: Record<string, Record<string, ThemeComponent>> = {
  default: {
    blog: Blog,
    'blog-detail': BlogDetail,
    cta: Cta,
    faq: Faq,
    'features-accordion': FeaturesAccordion,
    'features-flow': FeaturesFlow,
    'features-list': FeaturesList,
    'features-media': FeaturesMedia,
    'features-step': FeaturesStep,
    features: Features,
    footer: Footer,
    header: Header,
    hero: Hero,
    logos: Logos,
    'page-detail': PageDetail,
    pricing: Pricing,
    'showcases-flow': ShowcasesFlow,
    showcases: Showcases,
    'social-avatars': SocialAvatars,
    stats: Stats,
    subscribe: Subscribe,
    testimonials: Testimonials,
    updates: Updates,
  },
};

/**
 * get active theme
 */
export function getActiveTheme(): string {
  const theme = envConfigs.theme as string;

  if (theme) {
    return theme;
  }

  return defaultTheme;
}

/**
 * load theme page
 */
export async function getThemePage(pageName: string, theme?: string) {
  const loadTheme = theme || getActiveTheme();
  const component =
    themePages[loadTheme]?.[pageName] ?? themePages[defaultTheme]?.[pageName];

  if (!component) {
    throw new Error(`Theme page "${pageName}" not found for "${loadTheme}"`);
  }

  return component;
}

/**
 * load theme layout
 */
export async function getThemeLayout(layoutName: string, theme?: string) {
  const loadTheme = theme || getActiveTheme();
  const component =
    themeLayouts[loadTheme]?.[layoutName] ??
    themeLayouts[defaultTheme]?.[layoutName];

  if (!component) {
    throw new Error(`Theme layout "${layoutName}" not found for "${loadTheme}"`);
  }

  return component;
}

/**
 * load theme block
 */
export async function getThemeBlock(blockName: string, theme?: string) {
  const loadTheme = theme || getActiveTheme();
  const component =
    themeBlocks[loadTheme]?.[blockName] ?? themeBlocks[defaultTheme]?.[blockName];

  if (!component) {
    throw new Error(`Theme block "${blockName}" not found for "${loadTheme}"`);
  }

  return component;
}
