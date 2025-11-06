# Architecture Overview

## System Design

This application follows a client-server architecture where:
- **Django Backend** serves as the single source of truth
- **React Web App** and **iOS App** (future) both consume the same REST API
- **Gmail API** is accessed only through the Django backend for security and consistency

## Component Breakdown

### Backend (Django)

#### Models (`emails/models.py`)
- **EmailAccount**: Stores Gmail account credentials and sync status
  - OAuth tokens (access_token, refresh_token)
  - User association
  - Last sync timestamp
  
- **Email**: Stores individual email messages
  - Full email content (subject, body, headers)
  - Gmail-specific metadata (gmail_id, thread_id, labels)
  - Read/unread status

#### Gmail Service (`emails/gmail_service.py`)
Handles all Gmail API interactions:
- **OAuth Flow**: Authorization URL generation and token exchange
- **Token Management**: Automatic token refresh when expired
- **Email Fetching**: Retrieves messages from Gmail API
- **Email Parsing**: Converts Gmail API format to our database format

#### API Endpoints (`emails/views.py`)
- `GET /api/accounts/` - List user's email accounts
- `POST /api/accounts/{id}/sync/` - Manually sync emails
- `GET /api/auth/gmail/start/` - Initiate Gmail OAuth
- `GET /api/auth/gmail/callback/` - Handle OAuth callback
- `GET /api/emails/` - List emails (with filters)
- `GET /api/emails/{id}/` - Get email details

#### Background Tasks (`emails/tasks.py`)
Celery tasks for periodic email syncing:
- `sync_all_accounts()` - Sync all active accounts
- `sync_account(account_id)` - Sync specific account

### Frontend (React)

#### Components
- **App.js**: Main application container
- **EmailAccountList**: Sidebar showing connected accounts
- **EmailList**: Main panel showing email list
- **EmailDetail**: Right panel showing email content

#### API Service (`services/api.js`)
Centralized API client handling:
- Session-based authentication (cookies)
- Error handling
- Request/response formatting

## Data Flow

### Connecting a Gmail Account

1. User clicks "Connect Gmail" in React app
2. React calls `GET /api/auth/gmail/start/`
3. Backend generates OAuth URL and returns it
4. User is redirected to Google OAuth consent screen
5. User authorizes the app
6. Google redirects to `/api/auth/gmail/callback/` with authorization code
7. Backend exchanges code for tokens
8. Backend creates/updates EmailAccount record
9. Backend performs initial email sync
10. Backend redirects to frontend
11. Frontend refreshes and shows the new account

### Viewing Emails

1. User selects an account in React app
2. React calls `GET /api/emails/?account={id}`
3. Backend queries Email model filtered by account
4. Backend returns serialized email list
5. React displays emails in EmailList component
6. User clicks an email
7. React calls `GET /api/emails/{id}/`
8. Backend returns full email details
9. React displays email in EmailDetail component

### Syncing Emails

**Manual Sync:**
1. User clicks sync button
2. React calls `POST /api/accounts/{id}/sync/`
3. Backend calls `GmailService.sync_emails()`
4. Gmail API is queried for new messages
5. New emails are parsed and saved to database
6. Response includes count of synced emails

**Automatic Sync (Future):**
1. Celery worker runs periodic task (e.g., every 5 minutes)
2. Task calls `sync_all_accounts()`
3. Each account is synced via Gmail API
4. New emails are saved to database
5. WebSocket notification sent to connected clients (future)

## Security Considerations

1. **OAuth Tokens**: Stored securely in database, never exposed to frontend
2. **Token Refresh**: Automatic refresh prevents token expiration issues
3. **Session Authentication**: Django sessions used for API authentication
4. **CORS**: Configured to only allow requests from approved origins
5. **Environment Variables**: Sensitive credentials stored in `.env` file

## Scalability Considerations

### Current Limitations
- Synchronous email fetching (one at a time)
- No pagination for large email lists
- All emails loaded at once

### Future Improvements
- Pagination for email lists
- Incremental sync (only fetch new emails since last sync)
- Caching layer for frequently accessed emails
- Database indexing optimization
- WebSocket for real-time updates (avoid polling)

## Gmail API Usage

### Scopes Used
- `gmail.readonly`: Read emails
- `gmail.modify`: Mark as read/unread, star/unstar (future)

### Rate Limits
- Gmail API has quota limits (per user per second)
- Current implementation fetches in batches
- Consider implementing rate limiting/throttling for production

### Email Storage
- Currently stores full email content in database
- Consider storing only metadata and fetching content on-demand for large deployments
- Or implement email archival to cheaper storage

## iOS App Integration (Future)

The iOS app will consume the same Django REST API:
- Use URLSession for HTTP requests
- Store session cookies for authentication
- Implement same OAuth flow (redirect to web view for Google login)
- Use same data models mapped to Swift structs
- Share business logic through API calls

This ensures consistency between web and mobile experiences.

