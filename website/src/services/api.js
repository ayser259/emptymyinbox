const djangoDebug =
  (process.env.REACT_APP_DJANGO_DEBUG || process.env.DJANGO_DEBUG || '')
    .toLowerCase();

const DEFAULT_PROD_URL = 'https://emptymyinbox-t4zx.onrender.com/api';
const DEFAULT_DEV_URL = 'http://localhost:8000/api';

const API_BASE_URL =
  process.env.REACT_APP_API_URL ||
  (['1', 'true', 'yes'].includes(djangoDebug) ? DEFAULT_DEV_URL : DEFAULT_PROD_URL);

class ApiService {
  constructor() {
    this.baseURL = API_BASE_URL;
    this.accessToken = localStorage.getItem('accessToken');
    this.refreshToken = localStorage.getItem('refreshToken');
  }

  setTokens(accessToken, refreshToken) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    if (accessToken) {
      localStorage.setItem('accessToken', accessToken);
    } else {
      localStorage.removeItem('accessToken');
    }
    if (refreshToken) {
      localStorage.setItem('refreshToken', refreshToken);
    } else {
      localStorage.removeItem('refreshToken');
    }
  }

  clearTokens() {
    this.accessToken = null;
    this.refreshToken = null;
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
  }

  getAuthHeaders() {
    const headers = {};
    if (this.accessToken) {
      headers['Authorization'] = `Bearer ${this.accessToken}`;
    }
    return headers;
  }

  async refreshAccessToken() {
    if (!this.refreshToken) {
      throw new Error('No refresh token available');
    }

    try {
      const response = await fetch(`${this.baseURL}/auth/token/refresh/`, {
        method: 'POST',
        credentials: 'include', // Include cookies for session management
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ refresh: this.refreshToken }),
      });

      if (!response.ok) {
        throw new Error('Failed to refresh token');
      }

      const data = await response.json();
      this.setTokens(data.access, this.refreshToken);
      return data.access;
    } catch (error) {
      this.clearTokens();
      throw error;
    }
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    
    // For auth endpoints (login/register), don't include auth headers
    const isAuthEndpoint = endpoint.startsWith('/auth/login/') || 
                          endpoint.startsWith('/auth/register/');
    
    let config = {
      credentials: 'include', // Include cookies (session cookies) for cross-origin requests
      headers: {
        'Content-Type': 'application/json',
        ...(isAuthEndpoint ? {} : this.getAuthHeaders()),
        ...options.headers,
      },
      ...options,
    };

    let response = await fetch(url, config);
    
    // If unauthorized, try to refresh token and retry once (but not for auth endpoints)
    if (response.status === 401 && 
        this.refreshToken && 
        !isAuthEndpoint && 
        endpoint !== '/auth/token/refresh/') {
      try {
        await this.refreshAccessToken();
        config.headers = {
          ...this.getAuthHeaders(),
          ...options.headers,
        };
        config.credentials = 'include'; // Ensure credentials are included on retry
        response = await fetch(url, config);
      } catch (error) {
        // Refresh failed, clear tokens
        this.clearTokens();
        throw new Error('Session expired. Please login again.');
      }
    }
    
    if (!response.ok) {
      let errorData;
      try {
        errorData = await response.json();
      } catch (e) {
        errorData = { error: `Request failed with status ${response.status}` };
      }
      
      // Handle different error formats
      const errorMessage = errorData.error || 
                          errorData.detail || 
                          (Array.isArray(errorData.non_field_errors) ? errorData.non_field_errors[0] : null) ||
                          `HTTP error! status: ${response.status}`;
      throw new Error(errorMessage);
    }

    return response.json();
  }

  // Authentication endpoints
  async register(userData) {
    const response = await this.request('/auth/register/', {
      method: 'POST',
      body: JSON.stringify(userData),
    });
    if (response.tokens) {
      this.setTokens(response.tokens.access, response.tokens.refresh);
    }
    return response;
  }

  async login(credentials) {
    try {
      const response = await this.request('/auth/login/', {
        method: 'POST',
        body: JSON.stringify(credentials),
      });
      if (response.tokens) {
        this.setTokens(response.tokens.access, response.tokens.refresh);
      }
      return response;
    } catch (error) {
      throw error;
    }
  }

  async logout() {
    try {
      if (this.refreshToken) {
        await this.request('/auth/logout/', {
          method: 'POST',
          body: JSON.stringify({ refresh: this.refreshToken }),
        });
      }
    } catch (error) {
      // Silently fail on logout - token may already be invalid
      // This is acceptable as the user is logging out anyway
    } finally {
      this.clearTokens();
    }
  }

  async getUser() {
    return this.request('/auth/user/');
  }

  // Email Account endpoints
  async getAccounts() {
    return this.request('/accounts/');
  }

  async addGmailAccount() {
    const response = await this.request('/auth/gmail/start/');
    return response.authorization_url;
  }

  async syncAccount(accountId) {
    return this.request(`/accounts/${accountId}/sync/`, { method: 'POST' });
  }

  // Email endpoints
  async getEmails(params = {}) {
    const queryString = new URLSearchParams(params).toString();
    return this.request(`/emails/${queryString ? `?${queryString}` : ''}`);
  }

  async getEmail(emailId) {
    return this.request(`/emails/${emailId}/`);
  }
}

export default new ApiService();



