'use client';

import { useState } from 'react';

import { Link, useRouter } from '@/core/i18n/navigation';
import { detectImage, detectText, type DetectResult } from '@/lib/api';

const RESULT_STORAGE_KEY = 'detect-result';
const RESULT_STORAGE_KEYS = [RESULT_STORAGE_KEY, 'latest-detect-result'] as const;

function persistResult(result: DetectResult) {
  const serialized = JSON.stringify(result);

  for (const key of RESULT_STORAGE_KEYS) {
    sessionStorage.setItem(key, serialized);
    localStorage.setItem(key, serialized);
  }
}

export default function DetectPage() {
  const router = useRouter();

  const [detectType, setDetectType] = useState<'text' | 'image'>('text');
  const [textValue, setTextValue] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');

    if (detectType === 'text' && !textValue.trim()) {
      setError('请输入要检测的文本。');
      return;
    }

    if (detectType === 'image' && !selectedFile) {
      setError('请先上传待检测图片。');
      return;
    }

    try {
      setLoading(true);

      let result: DetectResult;

      if (detectType === 'text') {
        result = await detectText(textValue);
      } else {
        result = await detectImage(selectedFile);
      }

      persistResult(result);
      router.push('/result');
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : '检测失败，请稍后重试。');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="bg-background text-foreground">
      <section className="mx-auto flex max-w-4xl flex-col gap-6 px-6 py-16 md:py-24">
        <div className="text-center">
          <p className="text-muted-foreground mb-4 text-sm tracking-[0.3em] uppercase">
            Detection Workspace
          </p>
          <h1 className="text-3xl font-bold tracking-tight md:text-5xl">
            开始检测文本或图片内容
          </h1>
          <p className="text-muted-foreground mx-auto mt-4 max-w-2xl text-sm leading-7 md:text-base">
            当前版本优先支持文本与图片的规则检测，系统将输出风险等级、风险分数、可疑点与详细指标。
          </p>
        </div>

        <div className="space-y-6 rounded-2xl border bg-card p-6 shadow-sm">
          <div className="space-y-2">
            <h2 className="text-xl font-semibold">检测入口</h2>
            <p className="text-muted-foreground text-sm leading-7">
              默认优先支持文本检测；图片检测支持上传后进行规则分析。
            </p>
          </div>

          <div className="grid grid-cols-2 gap-2 rounded-xl border bg-muted/30 p-1">
            <button
              type="button"
              onClick={() => setDetectType('text')}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                detectType === 'text'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              文本检测
            </button>
            <button
              type="button"
              onClick={() => setDetectType('image')}
              className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                detectType === 'image'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              图片检测
            </button>
          </div>

          {detectType === 'text' ? (
            <div className="space-y-2">
              <p className="text-sm font-medium">输入待检测文本</p>
              <textarea
                value={textValue}
                onChange={(e) => setTextValue(e.target.value)}
                placeholder="请输入新闻、描述、评论或其他文本内容进行分析……"
                className="min-h-[220px] w-full rounded-xl border border-input bg-background px-4 py-3 text-sm outline-none transition focus:border-ring focus:ring-2 focus:ring-ring/20"
              />
            </div>
          ) : (
            <div className="space-y-2">
              <p className="text-sm font-medium">上传待检测图片</p>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => setSelectedFile(e.target.files?.[0] || null)}
                className="w-full rounded-xl border border-input bg-background px-4 py-3 text-sm"
              />
              {selectedFile && (
                <p className="text-muted-foreground text-sm">已选择：{selectedFile.name}</p>
              )}
            </div>
          )}

          {error && (
            <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-600">
              {error}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={handleSubmit}
              disabled={loading}
              className="inline-flex h-11 items-center justify-center rounded-md bg-primary px-6 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {loading ? '分析中...' : '开始分析'}
            </button>
            <Link
              href="/"
              className="inline-flex h-11 items-center justify-center rounded-md border border-input bg-background px-6 text-sm font-medium transition-colors hover:bg-accent hover:text-accent-foreground"
            >
              返回首页
            </Link>
          </div>

          <div className="text-muted-foreground text-sm leading-7">
            当前结果基于规则检测，仅用于风险提示，不代表绝对判定。建议结合内容来源、上下文与人工复核进行综合判断。
          </div>
        </div>
      </section>
    </main>
  );
}
