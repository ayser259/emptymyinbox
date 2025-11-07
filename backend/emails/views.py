import logging

from django.shortcuts import redirect
from django.contrib.auth import authenticate, get_user_model
from rest_framework import viewsets, status
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import EmailAccount, Email
from .serializers import (
    EmailAccountSerializer,
    EmailSerializer,
    EmailListSerializer,
    UserRegistrationSerializer,
    UserSerializer,
)
from .gmail_service import GmailService

logger = logging.getLogger(__name__)


class EmailAccountViewSet(viewsets.ModelViewSet):
    """ViewSet for managing email accounts"""
    serializer_class = EmailAccountSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return EmailAccount.objects.filter(user=self.request.user, is_active=True)

    @action(detail=True, methods=["post"])
    def sync(self, request, pk=None):
        """Manually trigger email sync for an account"""
        account = self.get_object()
        try:
            count = GmailService.sync_emails(account)
            return Response({"synced": count, "message": f"Synced {count} new emails"})
        except Exception as e:
            return Response(
                {"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class EmailViewSet(viewsets.ReadOnlyModelViewSet):
    """ViewSet for viewing emails"""
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Only show emails from accounts belonging to the user
        user_accounts = EmailAccount.objects.filter(user=self.request.user, is_active=True)
        queryset = Email.objects.filter(account__in=user_accounts)
        
        # Apply filters
        account_id = self.request.query_params.get("account", None)
        if account_id:
            queryset = queryset.filter(account_id=account_id)
        is_read = self.request.query_params.get("is_read", None)
        if is_read is not None:
            queryset = queryset.filter(is_read=is_read.lower() == "true")
        return queryset

    def get_serializer_class(self):
        if self.action == "list":
            return EmailListSerializer
        return EmailSerializer


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def gmail_auth_start(request):
    """Start Gmail OAuth flow"""
    try:
        auth_url, state = GmailService.get_authorization_url()
        # Store state and user_id in session for verification
        request.session["gmail_oauth_state"] = state
        request.session["gmail_oauth_user_id"] = request.user.id
        return Response({"authorization_url": auth_url})
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
@permission_classes([AllowAny])
def gmail_auth_callback(request):
    """Handle Gmail OAuth callback"""
    code = request.query_params.get("code")
    state = request.query_params.get("state")

    # Verify state matches session
    session_state = request.session.get("gmail_oauth_state")
    if not session_state or session_state != state:
        return Response(
            {"error": "Invalid state parameter"}, status=status.HTTP_400_BAD_REQUEST
        )

    # Get user_id from session (stored during auth_start)
    user_id = request.session.get("gmail_oauth_user_id")
    if not user_id:
        return Response(
            {"error": "User session not found. Please start the OAuth flow again."}, 
            status=status.HTTP_400_BAD_REQUEST
        )

    # Get the user object
    User = get_user_model()
    try:
        user = User.objects.get(id=user_id)
    except User.DoesNotExist:
        return Response(
            {"error": "User not found"}, 
            status=status.HTTP_400_BAD_REQUEST
        )

    if not code:
        return Response(
            {"error": "Missing authorization code"}, status=status.HTTP_400_BAD_REQUEST
        )

    try:
        # Exchange code for tokens
        tokens = GmailService.exchange_code_for_tokens(code)

        # Get user's email from Gmail
        # Create a temporary account to get the email
        temp_account = EmailAccount(
            user=user,
            email="temp@temp.com",  # Temporary
            access_token=tokens["access_token"],
            refresh_token=tokens.get("refresh_token"),
            token_expiry=tokens.get("token_expiry"),
        )
        temp_account.save()

        try:
            user_email = GmailService.get_user_email(temp_account)
        except Exception as e:
            temp_account.delete()
            logger.error(f"Failed to get user email for temp account: {e}", exc_info=True)
            raise

        # Check if account already exists
        email_account, created = EmailAccount.objects.get_or_create(
            user=user,
            email=user_email,
            defaults={
                "access_token": tokens["access_token"],
                "refresh_token": tokens.get("refresh_token"),
                "token_expiry": tokens.get("token_expiry"),
            },
        )

        if not created:
            # Update existing account
            email_account.access_token = tokens["access_token"]
            if tokens.get("refresh_token"):
                email_account.refresh_token = tokens.get("refresh_token")
            email_account.token_expiry = tokens.get("token_expiry")
            email_account.is_active = True
            email_account.save()

        # Delete temp account if it was created
        if temp_account.email == "temp@temp.com":
            temp_account.delete()

        # Perform initial sync
        try:
            GmailService.sync_emails(email_account, max_results=100)
        except Exception as e:
            logger.error(f"Error during initial sync for account {email_account.email}: {e}", exc_info=True)

        # Clean up session
        del request.session["gmail_oauth_state"]
        del request.session["gmail_oauth_user_id"]

        # Redirect to frontend with success
        frontend_url = "http://localhost:3000"
        return redirect(f"{frontend_url}?account_connected=true")

    except Exception as e:
        return Response(
            {"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


# Authentication Views
class RegisterView(APIView):
    """Register a new user"""
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = UserRegistrationSerializer(data=request.data)
        if serializer.is_valid():
            user = serializer.save()
            refresh = RefreshToken.for_user(user)
            return Response(
                {
                    "user": UserSerializer(user).data,
                    "tokens": {
                        "refresh": str(refresh),
                        "access": str(refresh.access_token),
                    },
                },
                status=status.HTTP_201_CREATED,
            )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LoginView(APIView):
    """Login user and return JWT tokens"""
    permission_classes = [AllowAny]

    def post(self, request):
        try:
            username = request.data.get("username")
            password = request.data.get("password")

            if not username or not password:
                return Response(
                    {"error": "Username and password are required"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            user = authenticate(username=username, password=password)
            if user is None:
                return Response(
                    {"error": "Invalid username or password"}, 
                    status=status.HTTP_401_UNAUTHORIZED
                )

            # Check if user is active
            if not user.is_active:
                return Response(
                    {"error": "User account is disabled"},
                    status=status.HTTP_401_UNAUTHORIZED
                )

            refresh = RefreshToken.for_user(user)
            return Response(
                {
                    "user": UserSerializer(user).data,
                    "tokens": {
                        "refresh": str(refresh),
                        "access": str(refresh.access_token),
                    },
                },
                status=status.HTTP_200_OK,
            )
        except Exception as e:
            logger.error(f"Login error: {str(e)}", exc_info=True)
            return Response(
                {"error": "An error occurred during login. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# Keep function-based views for backward compatibility
register = RegisterView.as_view()
login = LoginView.as_view()


class LogoutView(APIView):
    """Logout user by blacklisting refresh token"""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get("refresh")
            if refresh_token:
                token = RefreshToken(refresh_token)
                token.blacklist()
            return Response({"message": "Successfully logged out"}, status=status.HTTP_200_OK)
        except Exception as e:
            return Response(
                {"error": "Invalid token"}, status=status.HTTP_400_BAD_REQUEST
            )


class UserDetailView(APIView):
    """Get current user details"""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data, status=status.HTTP_200_OK)


# Keep function-based views for backward compatibility
logout = LogoutView.as_view()
user_detail = UserDetailView.as_view()
