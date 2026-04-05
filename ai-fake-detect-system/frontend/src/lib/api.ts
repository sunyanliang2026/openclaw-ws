export type DetectResult = {
  success: boolean;
  type: 'text' | 'image';
  risk_level: 'low' | 'medium' | 'high';
  score: number;
  points: string[];
  details: Record<string, unknown>;
  message?: string;
};

const DETECT_API_BASE_URL = '/api/detect';

async function handleResponse(response: Response): Promise<DetectResult> {
  const data = await response.json();

  if (!response.ok || !data.success) {
    throw new Error(data.message || 'Request failed');
  }

  return data as DetectResult;
}

export async function detectText(content: string): Promise<DetectResult> {
  const response = await fetch(`${DETECT_API_BASE_URL}/text`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ content }),
  });

  return handleResponse(response);
}

export async function detectImage(file: File): Promise<DetectResult> {
  const formData = new FormData();
  formData.append('file', file);

  const response = await fetch(`${DETECT_API_BASE_URL}/image`, {
    method: 'POST',
    body: formData,
  });

  return handleResponse(response);
}
