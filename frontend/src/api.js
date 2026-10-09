const baseUrl = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '');

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

async function request(path, { token, method = 'GET', body, signal } = {}) {
  let response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method,
      signal,
      cache: 'no-store',
      headers: {
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  } catch (error) {
    if (error.name === 'AbortError') throw error;
    throw new ApiError('Tidak dapat terhubung ke server lokal. Periksa API di port 8000.', 0);
  }
  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new ApiError(payload?.detail || `Permintaan gagal (${response.status}).`, response.status);
  }
  return response.status === 204 ? null : response.json();
}

export const api = {
  login: (email, password) => request('/api/auth/login', { method: 'POST', body: { email, password } }),
  me: (token) => request('/api/auth/me', { token }),
  logout: (token) => request('/api/auth/logout', { token, method: 'POST' }),
  changePassword: (token, current_password, new_password) =>
    request('/api/auth/change-password', { token, method: 'POST', body: { current_password, new_password } }),
  summary: (token, signal) => request('/api/summary', { token, signal }),
  pulse: (token, days = 7, signal) => request(`/api/operations/pulse?days=${days}`, { token, signal }),
  dropPoints: (token, signal) => request('/api/drop-points', { token, signal }),
  dailyReport: (token, signal) => request('/api/reports/daily', { token, signal }),
  detail: (token, id, signal) => request(`/api/drop-points/${encodeURIComponent(id)}`, { token, signal }),
  section: (token, id, section, signal) =>
    request(`/api/drop-points/${encodeURIComponent(id)}/${section}`, { token, signal }),
  dpPulse: (token, id, days = 7, signal) =>
    request(`/api/drop-points/${encodeURIComponent(id)}/pulse?days=${days}`, { token, signal }),
  parcelQueue: (token, id, signal) =>
    request(`/api/drop-points/${encodeURIComponent(id)}/parcel-queue`, { token, signal }),
};
