import { NextRequest, NextResponse } from 'next/server';

import { envConfigs } from '@/config';

const API_BASE_URL = envConfigs.api_base_url.replace(/\/$/, '');

export async function POST(req: NextRequest) {
  let formData: FormData;

  try {
    formData = await req.formData();
  } catch {
    return NextResponse.json(
      {
        success: false,
        message: 'invalid form data',
      },
      { status: 400 }
    );
  }

  const file = formData.get('file');
  if (!(file instanceof File)) {
    return NextResponse.json(
      {
        success: false,
        message: 'no file uploaded',
      },
      { status: 400 }
    );
  }

  const forwardFormData = new FormData();
  forwardFormData.append('file', file, file.name);

  try {
    const response = await fetch(`${API_BASE_URL}/detect/image`, {
      method: 'POST',
      body: forwardFormData,
      cache: 'no-store',
    });
    const data = await response.json();

    return NextResponse.json(data, { status: response.status });
  } catch (error) {
    console.error('Image detect proxy error:', error);

    return NextResponse.json(
      {
        success: false,
        message: 'backend service unavailable',
      },
      { status: 502 }
    );
  }
}
