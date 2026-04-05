import { NextRequest, NextResponse } from 'next/server';

import { envConfigs } from '@/config';

const API_BASE_URL = envConfigs.api_base_url.replace(/\/$/, '');

export async function POST(req: NextRequest) {
  let payload: unknown;

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

  try {
    const response = await fetch(`${API_BASE_URL}/detect/text`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
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
