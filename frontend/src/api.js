async function request(path, options = {}) {
  const response = await fetch(path, {
    method: options.method ?? 'GET',
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers ?? {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  })

  if (!response.ok) {
    let message = `Request failed: ${response.status}`

    try {
      const payload = await response.json()
      message = payload?.error || payload?.message || message
    } catch {
      // Keep the fallback when the backend returns a non-JSON response.
    }

    throw new Error(message)
  }

  return response.json()
}

export const api = {
  products() {
    return request('/products')
  },
  createProduct(payload) {
    return request('/products', {
      method: 'POST',
      body: payload,
    })
  },
}
