// Talking to the server over HTTP (login state). The game itself goes over the WebSocket.

export type Me =
  | { state: 'in'; user: { id: number; name: string; guest: boolean } }
  | { state: 'name' }
  | { state: 'out' };

export async function getMe(): Promise<Me> {
  const res = await fetch('/api/me', { cache: 'no-store' });
  if (!res.ok) throw new Error(`/api/me: ${res.status}`);
  return (await res.json()) as Me;
}

/** Returns an error code, or null on success. */
export async function post(path: string, body: unknown = {}): Promise<string | null> {
  try {
    const res = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    if (res.ok) return null;
    const data = (await res.json().catch(() => ({}))) as { error?: string };
    return data.error ?? 'server_error';
  } catch {
    return 'offline';
  }
}
