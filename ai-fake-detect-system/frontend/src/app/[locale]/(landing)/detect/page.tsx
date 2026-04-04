'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

import { detectImage, detectText, type DetectResult } from '@/lib/api';
import Link from 'next/link';

import { Badge } from '@/shared/components/ui/badge';
import { Button } from '@/shared/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/shared/components/ui/card';
import { Input } from '@/shared/components/ui/input';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/tabs';
import { Textarea } from '@/shared/components/ui/textarea';

export default function DetectPage() {
  const router = useRouter();

  const [detectType, setDetectType] = useState<'text' | 'image'>('text');
  const [textValue, setTextValue] = useState('');
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');

    try {
      setLoading(true);

      let result: DetectResult;

      if (detectType === 'text') {
        if (!textValue.trim()) {
          setError('请输入要检测的文本。');
          return;
        }

        result = await detectText(textValue);
      } else {
        if (!selectedFile) {
          setError('请先上传待检测图片。');
          return;
        }

        result = await detectImage(selectedFile);
      }

      sessionStorage.setItem('detect-result', JSON.stringify(result));
      router.push('/result');
    } catch (err: any) {
      setError(err?.message || '检测失败，请稍后重试。');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="bg-background text-foreground">
      <section className="mx-auto flex max-w-4xl flex-col gap-6 px-6 py-16 md:py-24">
        <div className="text-center">
          <Badge variant="outline" className="mb-4">
            Detection Workspace
          </Badge>
          <h1 className="text-3xl font-bold tracking-tight md:text-5xl">
            开始检测文本或图片内容
          </h1>
          <p className="text-muted-foreground mx-auto mt-4 max-w-2xl text-sm leading-7 md:text-base">
            当前版本优先支持文本与图片的规则检测，系统将输出风险等级、风险分数、可疑点与详细指标。
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>检测入口</CardTitle>
            <CardDescription>
              默认优先支持文本检测；图片检测支持上传后进行规则分析。
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <Tabs
              value={detectType}
              onValueChange={(value) => setDetectType(value as 'text' | 'image')}
              className="w-full"
            >
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="text">文本检测</TabsTrigger>
                <TabsTrigger value="image">图片检测</TabsTrigger>
              </TabsList>

              <TabsContent value="text" className="space-y-4">
                <div className="space-y-2">
                  <p className="text-sm font-medium">输入待检测文本</p>
                  <Textarea
                    value={textValue}
                    onChange={(e) => setTextValue(e.target.value)}
                    placeholder="请输入新闻、描述、评论或其他文本内容进行分析……"
                    className="min-h-[220px]"
                  />
                </div>
              </TabsContent>

              <TabsContent value="image" className="space-y-4">
                <div className="space-y-2">
                  <p className="text-sm font-medium">上传待检测图片</p>
                  <Input
                    type="file"
                    accept="image/*"
                    onChange={(e) => setSelectedFile(e.target.files?.[0] || null)}
                  />
                  {selectedFile && (
                    <p className="text-muted-foreground text-sm">
                      已选择：{selectedFile.name}
                    </p>
                  )}
                </div>
              </TabsContent>
            </Tabs>

            {error && (
              <div className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-600">
                {error}
              </div>
            )}

            <div className="flex flex-wrap items-center gap-3">
              <Button onClick={handleSubmit} size="lg" disabled={loading}>
                {loading ? '分析中...' : '开始分析'}
              </Button>
              <Button asChild variant="outline" size="lg">
                <Link href="/">返回首页</Link>
              </Button>
            </div>

            <div className="text-muted-foreground text-sm leading-7">
              当前结果基于规则检测，仅用于风险提示，不代表绝对判定。建议结合内容来源、上下文与人工复核进行综合判断。
            </div>
          </CardContent>
        </Card>
      </section>
    </main>
  );
}
