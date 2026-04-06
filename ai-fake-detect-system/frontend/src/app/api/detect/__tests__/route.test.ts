import assert from 'node:assert/strict';
import test from 'node:test';

import { POST as imageDetectPost } from '@/app/api/detect/image/route';
import { POST as textDetectPost } from '@/app/api/detect/text/route';

function mockFetchOnce(status: number, payload: unknown) {
  const fetchMock = async () =>
    new Response(JSON.stringify(payload), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });

  globalThis.fetch = fetchMock as typeof fetch;
}

test('text route rejects non-json content-type', async () => {
  let fetchCalled = false;
  globalThis.fetch = (async () => {
    fetchCalled = true;
    throw new Error('fetch should not be called');
  }) as typeof fetch;

  const req = new Request('http://localhost/api/detect/text', {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: 'hello',
  });

  const res = await textDetectPost(req as never);
  const body = await res.json();

  assert.equal(res.status, 400);
  assert.equal(body.success, false);
  assert.equal(body.message, 'content-type must be application/json');
  assert.equal(fetchCalled, false);
});

test('text route trims content before forwarding', async () => {
  let forwardedBody = '';
  globalThis.fetch = (async (_url, init) => {
    forwardedBody = String(init?.body ?? '');

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  const req = new Request('http://localhost/api/detect/text', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ content: '  hello world  ' }),
  });

  const res = await textDetectPost(req as never);
  const body = await res.json();

  assert.equal(res.status, 200);
  assert.equal(body.success, true);
  assert.deepEqual(JSON.parse(forwardedBody), { content: 'hello world' });
});

test('image route rejects unsupported file type', async () => {
  let fetchCalled = false;
  globalThis.fetch = (async () => {
    fetchCalled = true;
    throw new Error('fetch should not be called');
  }) as typeof fetch;

  const formData = new FormData();
  formData.append(
    'file',
    new File([new Uint8Array([1, 2, 3])], 'sample.txt', { type: 'text/plain' })
  );

  const req = new Request('http://localhost/api/detect/image', {
    method: 'POST',
    body: formData,
  });

  const res = await imageDetectPost(req as never);
  const body = await res.json();

  assert.equal(res.status, 400);
  assert.equal(body.success, false);
  assert.equal(body.message, 'unsupported file type');
  assert.equal(fetchCalled, false);
});

test('image route forwards valid image upload', async () => {
  mockFetchOnce(200, { success: true });

  const formData = new FormData();
  formData.append(
    'file',
    new File([new Uint8Array([1, 2, 3])], 'sample.png', { type: 'image/png' })
  );

  const req = new Request('http://localhost/api/detect/image', {
    method: 'POST',
    body: formData,
  });

  const res = await imageDetectPost(req as never);
  const body = await res.json();

  assert.equal(res.status, 200);
  assert.equal(body.success, true);
});
