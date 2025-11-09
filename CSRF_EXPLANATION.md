# CSRF Protection: Should We Use It or Exempt It?

## Understanding CSRF Attacks

**CSRF (Cross-Site Request Forgery)** exploits the fact that browsers automatically send cookies with requests. Here's how it works:

1. User logs into `yourapp.com` → gets session cookie
2. User visits malicious `evil.com` 
3. `evil.com` makes a request to `yourapp.com/api/delete-account`
4. Browser automatically includes the session cookie → request succeeds!

**CSRF tokens prevent this** because:
- Only `yourapp.com` knows the CSRF token
- `evil.com` can't get the token (same-origin policy)
- Request fails without valid token

## Your Current Setup

Looking at your code:

1. **JWT tokens**: Stored in `localStorage`, sent in `Authorization: Bearer <token>` header
2. **Session authentication**: Also enabled in Django settings
3. **Cookies**: Using `credentials: 'include'` which sends cookies

## The Key Question: Are You Vulnerable?

### JWT in Authorization Headers = NOT Vulnerable to CSRF ✅
- Browsers **do NOT** automatically send custom headers
- `evil.com` cannot add `Authorization: Bearer <token>` header
- **CSRF exemption is safe** for JWT-only endpoints

### Session Cookies = Vulnerable to CSRF ⚠️
- Browsers **DO** automatically send cookies
- `evil.com` can trigger requests with your session cookie
- **CSRF protection is needed** for session-based endpoints

## Recommendation: Choose One Approach

### Option 1: Pure JWT (Recommended for APIs) ✅

**Remove session authentication from API endpoints:**

```python
# settings.py
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
        # Remove SessionAuthentication for API endpoints
    ],
}
```

**Pros:**
- ✅ No CSRF needed (headers aren't auto-sent)
- ✅ Works great for APIs (web + mobile)
- ✅ Simpler implementation
- ✅ Stateless (scales better)

**Cons:**
- ❌ Tokens in localStorage vulnerable to XSS (but CSRF doesn't help here anyway)
- ❌ Can't use Django admin with same auth (but that's fine)

**Current status:** You're already doing this! ✅

### Option 2: JWT in httpOnly Cookies + CSRF (Most Secure) 🔒

**Store JWT in httpOnly cookies instead of localStorage:**

```python
# Backend: Set JWT in httpOnly cookie
response.set_cookie(
    'access_token',
    token,
    httponly=True,
    secure=True,  # HTTPS only
    samesite='Lax'
)
```

**Pros:**
- ✅ More secure (XSS can't steal tokens)
- ✅ CSRF protection works properly
- ✅ Tokens automatically sent with requests

**Cons:**
- ❌ More complex (need CSRF token handling)
- ❌ Harder to implement in mobile apps
- ❌ Need to handle CSRF tokens in frontend

### Option 3: Hybrid (Current Setup) ⚠️

**Keep both JWT and Session authentication:**

**Pros:**
- ✅ Flexible (can use either)

**Cons:**
- ❌ Confusing (which one is used?)
- ❌ Session auth needs CSRF, JWT doesn't
- ❌ Security risk if session auth is used accidentally

## My Recommendation: Option 1 (Pure JWT)

**Why:**
1. You're building an API for web + iOS → JWT is perfect
2. Your tokens are already in headers → CSRF exemption is correct
3. Simpler and cleaner architecture
4. Industry standard for REST APIs

**What to do:**
1. ✅ Keep CSRF exemption (you're doing it right!)
2. ✅ Remove `SessionAuthentication` from API endpoints
3. ✅ Keep session auth only for Django admin (if needed)

## Security Considerations

### What CSRF Protects Against:
- ✅ Session cookie hijacking via malicious sites
- ❌ XSS attacks (different protection needed)
- ❌ Token theft (different protection needed)

### What You Still Need:
- ✅ HTTPS in production
- ✅ XSS protection (Content Security Policy, input sanitization)
- ✅ Token expiration and refresh
- ✅ Secure token storage (consider httpOnly cookies if XSS is a concern)

## Conclusion

**For your use case (API with JWT in headers):**
- ✅ **CSRF exemption is correct and safe**
- ✅ JWT tokens in Authorization headers are NOT vulnerable to CSRF
- ✅ This is the standard approach for REST APIs

**You're doing it right!** The current approach is appropriate for a JWT-based API.


