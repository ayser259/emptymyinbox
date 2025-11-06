# Empty My Inbox - Setup Guide

This guide will walk you through setting up the Gmail integration for your email management app.

## Architecture Overview

- **Backend**: Django REST API with Gmail API integration
- **Frontend**: React web application
- **Future**: iOS app (will use the same Django API)

## Prerequisites

1. Python 3.8+ installed
2. Node.js 14+ and npm installed
3. Redis (for Celery background tasks - optional for now)
4. A Google Cloud Project with Gmail API enabled

## Step 1: Set Up Google Cloud Project & Gmail API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the Gmail API:
   - Navigate to "APIs & Services" > "Library"
   - Search for "Gmail API"
   - Click "Enable"
4. Configure OAuth consent screen (if not already done):
   - In Google Cloud Console, go to "APIs & Services" > "OAuth consent screen"
   - If you see tabs like "Overview", "Branding", "Audience", "Clients", etc., you're in the right place
   - If this is your first time, select "External" (for testing/development) and click "CREATE"
   - Fill in the required fields:
     - App name: "Empty My Inbox" (or any name)
     - User support email: your email
     - Developer contact information: your email
   - Click "SAVE AND CONTINUE" through the remaining steps (or just click "SAVE" if you want to skip optional steps)
   - **Important**: You can come back to configure this later if needed. For now, just make sure you've saved the basic info.

5. Add Test Users (if using External app type):
   - While still in the OAuth consent screen, look for the **"Test users"** section (you may need to scroll down or find it in the sidebar/navigation)
   - If you selected "External" app type, you'll need to add test users before they can use your app
   - Click **"+ ADD USERS"** button (or "ADD TEST USERS" button)
   - Enter the email addresses of the Gmail accounts you want to use for testing
   - You can add multiple email addresses (one per line, or click "ADD" after each one)
   - Click **"ADD"** or **"SAVE"** to confirm
   - **Note**: Only the email addresses you add here (plus your own developer account) will be able to authenticate with your app during testing
   - **Important**: Test users will receive an email notification, but they can still use the app even if they haven't clicked the link in the email

6. Create OAuth 2.0 credentials:
   - In Google Cloud Console, go to "APIs & Services" > **"Credentials"** (this is a different page from OAuth consent screen)
   - Look for the **"+ CREATE CREDENTIALS"** button at the top of the page
   - Click it and select **"OAuth client ID"** from the dropdown menu
   - If you don't see the button, make sure you're on the "Credentials" tab (not "OAuth consent screen")
   - **You should now see the "Create OAuth client ID" dialog/page with:**
     - "Application type" dropdown at the top (this is where you select "Web application")
     - "Name" field (you can name it anything, e.g., "Empty My Inbox")
   - Select **"Web application"** from the "Application type" dropdown
   - Give it a name (e.g., "Empty My Inbox" or "Gmail Integration")
   - Scroll down to find the "Authorized redirect URIs" section
   - Click "ADD URI" button
   - Enter: `http://localhost:8000/api/auth/gmail/callback`
     **Important**: This is the "Authorized redirect URIs" field (not "Authorized domains" or "Authorized JavaScript origins"). The full URL with `http://` is required here.
   - Click "CREATE" button at the bottom
   - A popup will appear showing your Client ID and Client Secret
   - **Copy both values immediately** (you won't be able to see the secret again)
   - Save your Client ID and Client Secret (you'll need these for your `.env` file)

## Step 2: Backend Setup

```bash
cd backend

# Create a virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment variables
cp .env.example .env

# Edit .env and add your Gmail API credentials
# GMAIL_CLIENT_ID=your_client_id_here
# GMAIL_CLIENT_SECRET=your_client_secret_here

# Run migrations
python manage.py migrate

# Create a superuser (for Django admin)
python manage.py createsuperuser

# Start the development server
python manage.py runserver
```

The backend will be running at `http://localhost:8000`

## Step 3: Frontend Setup

```bash
cd website

# Install dependencies
npm install

# Start the development server
npm start
```

The frontend will be running at `http://localhost:3000`

## Step 4: Using the App

1. **Connect a Gmail Account**:
   - Open the app in your browser (`http://localhost:3000`)
   - Click "Connect Gmail"
   - You'll be redirected to Google to authorize the app
   - After authorization, you'll be redirected back and your emails will start syncing

2. **View Emails**:
   - Select an email account from the sidebar
   - Your emails will appear in the main panel
   - Click on an email to view its full content

3. **Sync Emails**:
   - Click the sync button (↻) next to an account to manually refresh emails
   - In the future, emails will sync automatically via Celery background tasks

## API Endpoints

- `GET /api/accounts/` - List all email accounts
- `POST /api/accounts/{id}/sync/` - Manually sync emails for an account
- `GET /api/auth/gmail/start/` - Start Gmail OAuth flow
- `GET /api/auth/gmail/callback/` - Gmail OAuth callback
- `GET /api/emails/` - List emails (supports `?account={id}&is_read={true|false}`)
- `GET /api/emails/{id}/` - Get email details

## Current Features

✅ Connect multiple Gmail accounts
✅ View email list with read/unread status
✅ View full email content (HTML and plain text)
✅ Filter emails by read/unread status
✅ Manual email sync

## Planned Features

- [ ] Automatic background email sync (Celery)
- [ ] Real-time email updates (WebSockets)
- [ ] Mark emails as read/unread
- [ ] Star/unstar emails
- [ ] Search functionality
- [ ] Email threads/conversations
- [ ] iOS app integration

## Troubleshooting

### Gmail OAuth Not Working

**"Invalid domain: must not specify the scheme" error:**
- This error occurs if you're trying to add the redirect URI to the wrong field
- Make sure you're adding it to **"Authorized redirect URIs"** in the OAuth client credentials (not "Authorized domains")
- "Authorized redirect URIs" should include the full URL: `http://localhost:8000/api/auth/gmail/callback`
- "Authorized domains" is a different field (in OAuth consent screen) and should NOT include `http://` or `https://`

**"Access blocked: This app's request is invalid" or "User not allowed" error:**
- This usually means the Gmail account you're trying to connect isn't listed as a test user
- Go to "APIs & Services" > "OAuth consent screen" > "Test users" section
- Add the email address you're trying to use to the test users list
- Wait a few moments for the changes to propagate, then try again

**Other common issues:**
- Make sure your redirect URI in Google Cloud Console matches exactly: `http://localhost:8000/api/auth/gmail/callback`
- Check that your `GMAIL_CLIENT_ID` and `GMAIL_CLIENT_SECRET` are set correctly in `.env`
- Verify you've selected "Web application" as the application type when creating the OAuth client
- If using External app type, ensure all test email addresses are added to the "Test users" list

### CORS Errors
- Make sure `corsheaders` middleware is enabled in Django settings
- Verify `CORS_ALLOWED_ORIGINS` includes your React dev server URL

### Email Sync Issues
- Check that your Gmail account has granted necessary permissions
- Verify token hasn't expired (will auto-refresh)
- Check Django server logs for error messages

## Security Notes

⚠️ **Important for Production**:
- Never commit `.env` file to git
- Use strong `SECRET_KEY` in production
- Set `DEBUG = False` in production
- Use HTTPS for OAuth redirect URIs
- Store tokens securely (consider encryption at rest)
- Use environment variables for all sensitive data

## Next Steps

1. Set up Celery for automatic email syncing
2. Add WebSocket support for real-time updates
3. Build iOS app using the same Django API
4. Add more email management features (archive, delete, etc.)

