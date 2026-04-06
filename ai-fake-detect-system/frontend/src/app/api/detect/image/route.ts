import { NextRequest, NextResponse } from 'next/server';

import { envConfigs } from '@/config';

const API_BASE_URL = envConfigs.api_base_url.replace(/\/$/, '');
const MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
]);

export async function POST(req: NextRequest) {
  let formData: FormData;
  const contentType = req.headers.get('content-type') ?? '';

  if (!contentType.includes('multipart/form-data')) {
    return NextResponse.json(
      {
        success: false,
        message: 'content-type must be multipart/form-data',
      },
      { status: 400 }
    );
  }

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

  if (!file.type || !ALLOWED_IMAGE_TYPES.has(file.type)) {
    return NextResponse.json(
      {
        success: false,
        message: 'unsupported file type',
      },
      { status: 400 }
    );
  }

  if (file.size <= 0) {
    return NextResponse.json(
      {
        success: false,
        message: 'empty file uploaded',
      },
      { status: 400 }
    );
  }

  if (file.size > MAX_IMAGE_SIZE_BYTES) {
    return NextResponse.json(
      {
        success: false,
        message: `file exceeds ${MAX_IMAGE_SIZE_BYTES} bytes`,
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
