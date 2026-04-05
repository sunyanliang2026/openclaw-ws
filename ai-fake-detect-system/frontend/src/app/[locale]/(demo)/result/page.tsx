'use client';

import { useMemo, useState } from 'react';

import { Link } from '@/core/i18n/navigation';
import type { DetectResult } from '@/lib/api';

const riskLabelMap = {
  low: '低风险',
  medium: '中风险',
  high: '高风险',
} as const;

const riskClassMap = {
  low: 'bg-green-50 text-green-700 border-green-200',
  medium: 'bg-orange-50 text-orange-700 border-orange-200',
  high: 'bg-red-50 text-red-700 border-red-200',
} as const;

const summaryMap = {
  text: {
    low: '系统未发现明显高风险伪造特征，但建议继续结合发布来源与上下文进行判断。',
    medium:
      '系统检测到部分可疑语言特征，文本可能存在模板化或重复性表达，建议进一步人工复核。',
    high:
      '系统检测到较多可疑语言特征，文本可能存在较明显的模板化、重复化或来源不明问题，建议重点核查。',
  },
  image: {
    low: '系统未发现明显高风险图像特征，但建议继续结合图片来源、拍摄背景与使用场景进行判断。',
    medium:
      '系统检测到部分异常图像特征，图片可能存在元数据异常或局部处理痕迹，建议进一步核查。',
    high:
      '系统检测到较多异常图像特征，图片可能存在明显处理痕迹或生成式特征，建议重点核查来源与细节。',
  },
} as const;

const detailLabelMap = {
  text: {
    length: '文本长度',
    sentence_count: '句子数量',
    repeat_ratio: '重复率',
    avg_sentence_length: '平均句长',
    template_hits: '模板命中数',
    has_source_hint: '来源提示',
  },
  image: {
    width: '图片宽度',
    height: '图片高度',
    has_exif: 'EXIF 信息',
    blur_score: '模糊度',
    smoothness_score: '平滑度',
  },
} as const;

const RESULT_STORAGE_KEYS = ['detect-result', 'latest-detect-result'] as const;

function formatValue(key: string, value: unknown) {
  if (value === null || value === undefined) {
    return '暂无';
  }

  if (typeof value === 'boolean') {
    return value ? '是' : '否';
  }

  if (Array.isArray(value)) {
    return value.length ? value.join(', ') : '无';
  }

  if (typeof value === 'number') {
    if (key === 'repeat_ratio') {
      return `${(value * 100).toFixed(2)}%`;
    }

    if (!Number.isInteger(value)) {
      return value.toFixed(2);
    }
  }

  return String(value);
}

function readStoredResult(): DetectResult | null {
  const storages = [sessionStorage, localStorage];

  for (const storage of storages) {
    for (const key of RESULT_STORAGE_KEYS) {
      const raw = storage.getItem(key);
      if (!raw) {
        continue;
      }

      try {
        return JSON.parse(raw) as DetectResult;
      } catch {
        storage.removeItem(key);
      }
    }
  }

  return null;
}

export default function ResultPage() {
  const [result] = useState<DetectResult | null>(() =>
    typeof window === 'undefined' ? null : readStoredResult()
  );

  const detailEntries = useMemo(() => {
    if (!result) return [];

    const labelMap = detailLabelMap[result.type];
    return Object.entries(labelMap).map(([key, label]) => ({
      key,
      label,
      value: formatValue(key, result.details?.[key]),
    }));
  }, [result]);

  if (!result) {
    return (
      <main className="bg-background text-foreground">
        <section className="mx-auto flex max-w-4xl flex-col gap-6 px-6 py-16 md:py-24">
          <div className="rounded-2xl border bg-card p-6 shadow-sm">
            <h2 className="text-xl font-semibold">检测结果</h2>
            <p className="text-muted-foreground mt-2 text-sm leading-7">
              暂无检测结果，请先返回检测页执行分析。
            </p>
            <Link
              href="/detect"
              className="mt-4 inline-flex h-11 items-center justify-center rounded-md bg-primary px-6 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
            >
              返回检测页
            </Link>
          </div>
        </section>
      </main>
    );
  }

  const summary = summaryMap[result.type][result.risk_level];

  return (
    <main className="bg-background text-foreground">
      <section className="mx-auto flex max-w-5xl flex-col gap-6 px-6 py-16 md:py-24">
        <div className="text-center">
          <p className="text-muted-foreground text-sm">Detection Result</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight md:text-5xl">检测结果</h1>
          <p className="text-muted-foreground mx-auto mt-4 max-w-2xl text-sm leading-7 md:text-base">
            以下为系统对当前内容的风险分析结果与关键指标展示。
          </p>
        </div>

        <div className="space-y-6 rounded-2xl border bg-card p-6 shadow-sm">
          <div>
            <h2 className="text-xl font-semibold">风险结论</h2>
            <p className="text-muted-foreground mt-2 text-sm leading-7">
              检测类型：{result.type === 'text' ? '文本检测' : '图片检测'}
            </p>
          </div>
          <div className="space-y-6">
            <div className="flex flex-wrap items-center gap-4">
              <span
                className={`inline-flex w-fit items-center justify-center rounded-md border px-2 py-0.5 text-xs font-medium ${riskClassMap[result.risk_level]}`}
              >
                {riskLabelMap[result.risk_level]}
              </span>
              <div className="rounded-xl border bg-muted/40 px-5 py-3">
                <p className="text-muted-foreground text-xs">风险分数</p>
                <p className="text-3xl font-bold">{result.score}</p>
              </div>
            </div>
            <p className="text-muted-foreground text-sm leading-7">{summary}</p>
          </div>
        </div>

        <div className="rounded-2xl border bg-card p-6 shadow-sm">
          <h2 className="text-xl font-semibold">可疑点分析</h2>
          <p className="text-muted-foreground mt-2 text-sm leading-7">
            以下为系统识别出的主要可疑特征。
          </p>
          <div className="mt-6 space-y-3">
            {result.points?.length ? (
              result.points.map((point, index) => (
                <div
                  key={`${index}-${point}`}
                  className="rounded-lg border bg-muted/30 px-4 py-3 text-sm leading-7"
                >
                  {point}
                </div>
              ))
            ) : (
              <div className="rounded-lg border bg-muted/30 px-4 py-3 text-sm leading-7">
                暂无明显可疑点。
              </div>
            )}
          </div>
        </div>

        <div className="rounded-2xl border bg-card p-6 shadow-sm">
          <h2 className="text-xl font-semibold">详细指标</h2>
          <p className="text-muted-foreground mt-2 text-sm leading-7">
            这些指标用于辅助解释当前风险等级与分数。
          </p>
          <div className="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {detailEntries.map((item) => (
              <div key={item.key} className="rounded-xl border bg-muted/20 px-4 py-4">
                <p className="text-muted-foreground text-xs">{item.label}</p>
                <p className="mt-2 text-lg font-semibold">{item.value}</p>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-4 rounded-2xl border bg-card p-6 shadow-sm">
          <div>
            <h2 className="text-xl font-semibold">使用建议</h2>
            <p className="text-muted-foreground mt-2 text-sm leading-7">
              当前结果基于规则检测，仅用于风险提示，不代表绝对判定。
            </p>
          </div>
          <p className="text-muted-foreground text-sm leading-7">
            建议结合内容来源、上下文与人工复核进行综合判断。如果需要，可以返回检测页继续分析其他文本或图片。
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <Link
              href="/detect"
              className="inline-flex h-11 items-center justify-center rounded-md bg-primary px-6 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
            >
              返回重新检测
            </Link>
            <Link
              href="/"
              className="inline-flex h-11 items-center justify-center rounded-md border border-input bg-background px-6 text-sm font-medium transition-colors hover:bg-accent hover:text-accent-foreground"
            >
              返回首页
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
