# Empty My Inbox - iOS App

iOS app for Empty My Inbox that connects to the Django backend API.

## Features

- **Authentication**: Login and signup screens with JWT token management
- **Dashboard**: View email accounts and emails
- **Email Details**: View individual email content
- **Auto Token Refresh**: Automatically refreshes expired access tokens

## Setup

### Prerequisites

1. Xcode 14.0 or later
2. iOS 15.0 or later deployment target
3. Backend server running at `http://localhost:8000`

### Configuration

#### For iOS Simulator
The app is configured to connect to `http://localhost:8000` by default, which works fine for the iOS Simulator.

#### For Physical Device
If you want to test on a physical device, you'll need to:

1. Find your computer's IP address:
   ```bash
   # On macOS/Linux
   ifconfig | grep "inet " | grep -v 127.0.0.1
   
   # Or use:
   ipconfig getifaddr en0
   ```

2. Update the `baseURL` in `Services/APIService.swift`:
   ```swift
   private let baseURL = "http://YOUR_IP_ADDRESS:8000/api"
   ```

3. Make sure your backend allows connections from your device's IP address (check Django `ALLOWED_HOSTS` in `settings.py`)

### Running the App

1. Open `Emptymyinbox.xcodeproj` in Xcode
2. **Important**: If the new files don't appear in Xcode, you may need to add them:
   - Right-click on the `Emptymyinbox` folder in the Project Navigator
   - Select "Add Files to Emptymyinbox..."
   - Navigate to and select the `Services` and `Views` folders
   - Make sure "Copy items if needed" is unchecked and "Create groups" is selected
   - Ensure the "Emptymyinbox" target is checked
   - Click "Add"
3. Select a simulator or device
4. Build and run (⌘R)

## Project Structure

```
Emptymyinbox/
├── Services/
│   ├── APIService.swift      # API client for backend communication
│   └── AuthManager.swift     # Authentication state management
├── Views/
│   ├── LoginView.swift        # Login screen
│   ├── SignupView.swift       # Sign up screen
│   └── DashboardView.swift    # Main dashboard with accounts and emails
├── ContentView.swift          # Root view with navigation logic
└── EmptymyinboxApp.swift      # App entry point
```

## API Endpoints Used

- `POST /api/auth/register/` - User registration
- `POST /api/auth/login/` - User login
- `POST /api/auth/logout/` - User logout
- `GET /api/auth/user/` - Get current user
- `POST /api/auth/token/refresh/` - Refresh access token
- `GET /api/accounts/` - List email accounts
- `GET /api/emails/` - List emails
- `GET /api/emails/{id}/` - Get email details

## Authentication Flow

1. User logs in or signs up
2. Backend returns JWT access and refresh tokens
3. Tokens are stored securely using UserDefaults
4. Access token is included in Authorization header for all API requests
5. If access token expires (401), app automatically refreshes using refresh token
6. If refresh fails, user is logged out

## Notes

- The app uses SwiftUI for the user interface
- Async/await is used for all network requests
- JWT tokens are stored in UserDefaults (consider using Keychain for production)
- Error handling includes user-friendly error messages

