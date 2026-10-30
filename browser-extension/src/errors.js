// A sentence a person can act on for any failed request. Same rules as the web dashboard and the phone app.

const NETWORK = "Can't reach the server. Check your internet connection and try again.";

function cleanDetail(message) {
  return String(message).replace(/^Value error,\s*/i, '').trim();
}

/** `status` is the HTTP status (0 when there was no response), `data` the parsed JSON body if any. */
export function errorMessage(status, data) {
  if (!status) return NETWORK;
  const detail = data && data.detail;
  if (typeof detail === 'string' && detail.trim()) return cleanDetail(detail);
  if (Array.isArray(detail) && typeof detail[0]?.msg === 'string' && detail[0].msg.trim()) {
    return cleanDetail(detail[0].msg);
  }
  if (status === 401 || status === 403) return 'Your session has expired. Please sign in again.';
  if (status >= 500) return 'The server had a problem. Please try again in a moment.';
  return 'Something went wrong. Please try again.';
}

export class ApiError extends Error {
  constructor(status, data) {
    super(errorMessage(status, data));
    this.status = status;
  }
}
