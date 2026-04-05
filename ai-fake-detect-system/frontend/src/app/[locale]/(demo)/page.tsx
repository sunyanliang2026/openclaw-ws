import { Link } from '@/core/i18n/navigation';

export default function LandingPage() {
  return (
    <main className="bg-background text-foreground">
      <section className="mx-auto flex max-w-6xl flex-col gap-12 px-6 py-24 md:py-32">
        <div className="grid gap-10 md:grid-cols-[1.2fr_0.8fr] md:items-center">
          <div className="space-y-6">
            <p className="text-muted-foreground text-sm tracking-[0.3em] uppercase">
              AI Fake Detect System
            </p>
            <h1 className="text-4xl font-bold tracking-tight md:text-6xl">
              一个用于识别 AI 生成文本与图片风险的最小可演示系统
            </h1>
            <p className="text-muted-foreground max-w-2xl text-base leading-8 md:text-lg">
              当前版本聚焦文本检测、图片检测、风险评分与可疑点解释输出，适合比赛演示与快速检查。
            </p>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/detect"
                className="inline-flex h-11 items-center justify-center rounded-md bg-primary px-6 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
              >
                进入检测
              </Link>
              <Link
                href="/result"
                className="inline-flex h-11 items-center justify-center rounded-md border border-input bg-background px-6 text-sm font-medium transition-colors hover:bg-accent hover:text-accent-foreground"
              >
                查看结果页原型
              </Link>
            </div>
          </div>

          <div className="rounded-2xl border bg-card p-6 shadow-sm">
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="rounded-xl border bg-muted/30 p-4">
                <h2 className="text-lg font-semibold">文本检测</h2>
                <p className="text-muted-foreground mt-2 text-sm leading-7">
                  识别重复表达、模板化语言、来源提示等可疑语言特征。
                </p>
              </div>
              <div className="rounded-xl border bg-muted/30 p-4">
                <h2 className="text-lg font-semibold">图片检测</h2>
                <p className="text-muted-foreground mt-2 text-sm leading-7">
                  识别图像元数据缺失、模糊度和平滑度等可疑图像特征。
                </p>
              </div>
            </div>
            <div className="mt-4 rounded-xl border bg-muted/20 p-4">
              <h3 className="font-semibold">结果解释</h3>
              <p className="text-muted-foreground mt-2 text-sm leading-7">
                输出风险等级、风险分数与可疑点说明，辅助人工复核。
              </p>
            </div>
          </div>
        </div>

        <section className="grid gap-6 md:grid-cols-2">
          <div className="rounded-xl border bg-card p-6 shadow-sm">
            <p className="text-muted-foreground text-sm font-medium">文本案例展示</p>
            <h2 className="mt-2 text-xl font-semibold">模板化、重复化、来源不明</h2>
            <p className="text-muted-foreground mt-3 text-sm leading-7">
              用于展示系统如何捕捉重复表达、模板语言与来源提示信号。
            </p>
          </div>
          <div className="rounded-xl border bg-card p-6 shadow-sm">
            <p className="text-muted-foreground text-sm font-medium">图片案例展示</p>
            <h2 className="mt-2 text-xl font-semibold">元数据、模糊度、平滑度</h2>
            <p className="text-muted-foreground mt-3 text-sm leading-7">
              用于展示系统如何分析图片的基础可疑特征，并给出解释性结果。
            </p>
          </div>
        </section>

        <div className="rounded-xl border bg-muted/20 p-5 text-sm leading-7 text-muted-foreground">
          当前结果基于规则检测，仅用于风险提示，不代表绝对判定。建议结合内容来源、上下文与人工复核进行综合判断。
        </div>
      </section>
    </main>
  );
}
