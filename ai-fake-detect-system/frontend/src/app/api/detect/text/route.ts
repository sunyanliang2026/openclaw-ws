import { NextRequest, NextResponse } from 'next/server';

import { envConfigs } from '@/config';

const API_BASE_URL = envConfigs.api_base_url.replace(/\/$/, '');
const MAX_TEXT_LENGTH = 10_000;

export async function POST(req: NextRequest) {
  let payload: unknown;
  const contentType = req.headers.get('content-type') ?? '';

  if (!contentType.includes('application/json')) {
    return NextResponse.json(
      {
        success: false,
        message: 'content-type must be application/json',
      },
      { status: 400 }
    );
  }

  try {
    payload = await req.json();
  } catch {
    return NextResponse.json(
      {
        success: false,
        message: 'invalid request body',
      },
      { status: 400 }
    );
  }

  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    return NextResponse.json(
      {
        success: false,
        message: 'request body must be a JSON object',
      },
      { status: 400 }
    );
  }

  const { content } = payload as { content?: unknown };
  if (typeof content !== 'string') {
    return NextResponse.json(
      {
        success: false,
        message: 'content must be a string',
      },
      { status: 400 }
    );
  }

  const normalizedContent = content.trim();
  if (!normalizedContent) {
    return NextResponse.json(
      {
        success: false,
        message: 'text content is empty',
      },
      { status: 400 }
    );
  }

  if (normalizedContent.length > MAX_TEXT_LENGTH) {
    return NextResponse.json(
      {
        success: false,
        message: `text content exceeds ${MAX_TEXT_LENGTH} characters`,
      },
      { status: 400 }
    );
  }

  const normalizedPayload = {
    ...(payload as Record<string, unknown>),
    content: normalizedContent,
  };

  try {
    const response = await fetch(`${API_BASE_URL}/detect/text`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(normalizedPayload),
      cache: 'no-store',
    });
    const data = await response.json();

    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Text detect proxy error:', error);

    return NextResponse.json(
      {
        success: false,
        message: 'backend service unavailable',
      },
      { status: 502 }
    );
  }
}
