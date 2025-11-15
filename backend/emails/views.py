import logging
import secrets
from datetime import timedelta

from django.shortcuts import redirect
from django.conf import settings
from django.contrib.auth import authenticate
from django.urls import reverse
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import EmailAccount, Email, UserProfile, Filter, GmailOAuthState
from .serializers import (
    EmailAccountSerializer,
    EmailSerializer,
    EmailListSerializer,
    UserRegistrationSerializer,
    UserSerializer,
    UserProfileSerializer,
    LabelSerializer,
    FilterSerializer,
)
from .gmail_service import GmailService
from django.db.models import Q, Count
from django.db import connection

logger = logging.getLogger(__name__)
GMAIL_OAUTH_STATE_TTL = timedelta(minutes=15)


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
            count = GmailService.sync_emails(account, max_results=500)
            return Response({"synced": count, "message": f"Synced {count} new emails"})
        except Exception as e:
            return Response(
                {"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    @action(detail=False, methods=["post"])
    def sync_all(self, request):
        """Sync all accounts for the current user"""
        user_accounts = self.get_queryset()
        total_synced = 0
        total_filters_synced = 0
        errors = []
        
        for account in user_accounts:
            try:
                # Sync emails
                count = GmailService.sync_emails(account, max_results=500)
                total_synced += count
                
                # Sync filters
                try:
                    filter_count = GmailService.sync_filters(account)
                    total_filters_synced += filter_count
                except Exception as filter_error:
                    logger.warning(f"Error syncing filters for account {account.email}: {filter_error}", exc_info=True)
                    # Don't fail the whole sync if filters fail
            except Exception as e:
                errors.append(f"Error syncing {account.email}: {str(e)}")
                logger.error(f"Error syncing account {account.email}: {e}", exc_info=True)
        
        # Get most recent email timestamp
        user_account_ids = [acc.id for acc in user_accounts]
        most_recent_email = Email.objects.filter(account__in=user_account_ids).order_by('-received_at').first()
        
        response_data = {
            "synced": total_synced,
            "filters_synced": total_filters_synced,
            "message": f"Synced {total_synced} new emails and {total_filters_synced} filters",
            "most_recent_email_at": most_recent_email.received_at.isoformat() if most_recent_email else None,
        }
        
        if errors:
            response_data["errors"] = errors
        
        return Response(response_data, status=status.HTTP_200_OK)
    

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
        is_starred = self.request.query_params.get("is_starred", None)
        if is_starred is not None:
            queryset = queryset.filter(is_starred=is_starred.lower() == "true")
        
        # Search query
        search_query = self.request.query_params.get("q", None)
        if search_query:
            queryset = queryset.filter(
                Q(subject__icontains=search_query) |
                Q(sender__icontains=search_query) |
                Q(sender_name__icontains=search_query) |
                Q(snippet__icontains=search_query)
            )
        
        # Filter by label ID
        label_id = self.request.query_params.get("label", None)
        if label_id:
            if label_id == "__UNCATEGORIZED__":
                # For uncategorized, exclude emails that have any user labels
                user_account_ids = [acc.id for acc in user_accounts]
                # Get all user label IDs (excluding system labels)
                system_label_ids = {"INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"}
                user_label_ids = []
                for account in user_accounts:
                    try:
                        gmail_labels = GmailService.get_all_labels(account)
                        user_label_ids.extend([lid for lid in gmail_labels.keys() if lid not in system_label_ids])
                    except Exception as e:
                        logger.error(f"Error fetching labels for account {account.email}: {e}", exc_info=True)
                        continue
                
                if user_label_ids:
                    # Exclude emails that have any user labels
                    queryset = queryset.exclude(Q(labels__overlap=user_label_ids))
                # If no user labels exist, all emails are uncategorized
            else:
                # Filter emails that contain this label ID
                # For SQLite JSONField, use json_each in a subquery
                # For PostgreSQL, use contains with array syntax
                if connection.vendor == 'sqlite':
                    # SQLite JSON1: Check if label_id exists in the labels JSON array
                    # Using EXISTS with json_each to check if any element matches
                    queryset = queryset.extra(
                        where=["EXISTS (SELECT 1 FROM json_each(emails_email.labels) WHERE json_each.value = %s)"],
                        params=[label_id]
                    )
                else:
                    # PostgreSQL: use contains with array syntax
                    queryset = queryset.filter(labels__contains=[label_id])
        
        return queryset

    def get_serializer_class(self):
        if self.action == "list":
            return EmailListSerializer
        return EmailSerializer

    @action(detail=True, methods=["post"])
    def star(self, request, pk=None):
        """Star an email in Gmail and update local database"""
        email = self.get_object()
        try:
            # Update Gmail
            GmailService.modify_email_labels(
                email.account,
                email.gmail_id,
                add_labels=["STARRED"]
            )
            
            # Update local database
            email.is_starred = True
            # Update labels list
            if email.labels and "STARRED" not in email.labels:
                email.labels.append("STARRED")
            elif not email.labels:
                email.labels = ["STARRED"]
            email.save()
            
            serializer = self.get_serializer(email)
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error starring email {email.id}: {e}", exc_info=True)
            return Response(
                {"error": str(e)}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    @action(detail=True, methods=["post"])
    def unstar(self, request, pk=None):
        """Unstar an email in Gmail and update local database"""
        email = self.get_object()
        try:
            # Update Gmail
            GmailService.modify_email_labels(
                email.account,
                email.gmail_id,
                remove_labels=["STARRED"]
            )
            
            # Update local database
            email.is_starred = False
            # Update labels list
            if email.labels and "STARRED" in email.labels:
                email.labels.remove("STARRED")
            email.save()
            
            serializer = self.get_serializer(email)
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error unstarring email {email.id}: {e}", exc_info=True)
            return Response(
                {"error": str(e)}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    @action(detail=True, methods=["post"])
    def mark_read(self, request, pk=None):
        """Mark an email as read in Gmail and update local database"""
        email = self.get_object()
        try:
            # Update Gmail - remove UNREAD label
            GmailService.modify_email_labels(
                email.account,
                email.gmail_id,
                remove_labels=["UNREAD"]
            )
            
            # Update local database
            email.is_read = True
            # Update labels list
            if email.labels and "UNREAD" in email.labels:
                email.labels.remove("UNREAD")
            email.save()
            
            serializer = self.get_serializer(email)
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error marking email {email.id} as read: {e}", exc_info=True)
            return Response(
                {"error": str(e)}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def gmail_auth_start(request):
    """Start Gmail OAuth flow"""
    try:
        callback_url = request.build_absolute_uri(reverse("gmail-auth-callback"))
        state_token = secrets.token_urlsafe(32)

        # Cleanup any stale tokens for this user to avoid table bloat
        cutoff = timezone.now() - GMAIL_OAUTH_STATE_TTL
        GmailOAuthState.objects.filter(user=request.user, created_at__lt=cutoff).delete()

        redirect_uri_override = request.query_params.get("redirect_uri", "")
        GmailOAuthState.objects.create(
            state=state_token,
            user=request.user,
            redirect_uri=redirect_uri_override or "",
        )

        auth_url, _ = GmailService.get_authorization_url(
            redirect_uri=callback_url, state=state_token
        )
        return Response({"authorization_url": auth_url})
    except Exception as e:
        return Response({"error": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(["GET"])
@permission_classes([AllowAny])
def gmail_auth_callback(request):
    """Handle Gmail OAuth callback"""
    code = request.query_params.get("code")
    state = request.query_params.get("state")
    callback_url = request.build_absolute_uri(reverse("gmail-auth-callback"))

    if not state:
        return Response(
            {"error": "Missing state parameter"}, status=status.HTTP_400_BAD_REQUEST
        )

    try:
        oauth_state = GmailOAuthState.objects.get(state=state)
    except GmailOAuthState.DoesNotExist:
        return Response(
            {"error": "Invalid state parameter"}, status=status.HTTP_400_BAD_REQUEST
        )

    if oauth_state.created_at < timezone.now() - GMAIL_OAUTH_STATE_TTL:
        oauth_state.delete()
        return Response(
            {"error": "State parameter expired. Please restart the OAuth flow."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = oauth_state.user

    if not code:
        return Response(
            {"error": "Missing authorization code"}, status=status.HTTP_400_BAD_REQUEST
        )

    try:
        # Exchange code for tokens
        tokens = GmailService.exchange_code_for_tokens(code, redirect_uri=callback_url)

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

        # Perform initial sync inline
        try:
            GmailService.sync_emails(email_account, max_results=250)
            GmailService.sync_filters(email_account)
        except Exception as e:
            logger.error(
                f"Initial sync failed for account {email_account.email}: {e}",
                exc_info=True,
            )

        # Clean up oauth state
        redirect_override = oauth_state.redirect_uri
        oauth_state.delete()

        # Detect if request is from iOS app
        user_agent = request.META.get("HTTP_USER_AGENT", "").lower()
        is_ios = "iphone" in user_agent or "ipad" in user_agent or "ipod" in user_agent
        
        # Check for iOS app redirect parameter (can be passed via state or query param)
        redirect_param = (
            redirect_override
            or request.query_params.get("redirect_uri")
        )
        if redirect_param:
            # Use custom redirect URI if provided
            return redirect(f"{redirect_param}?account_connected=true")
        elif is_ios:
            # Default iOS app URL scheme
            return redirect("emptymyinbox://account_connected=true")
        else:
            # Default web redirect
            frontend_url = settings.FRONTEND_SUCCESS_URL
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


class UserProfileUpdateView(APIView):
    """Update user profile (state, zip_code)"""
    permission_classes = [IsAuthenticated]

    def put(self, request):
        profile, created = UserProfile.objects.get_or_create(user=request.user)
        serializer = UserProfileSerializer(profile, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            # Return updated user data
            user_serializer = UserSerializer(request.user)
            return Response(user_serializer.data, status=status.HTTP_200_OK)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LabelsView(APIView):
    """Get all Gmail labels with unread counts"""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            # Get all active email accounts for the user
            user_accounts = EmailAccount.objects.filter(user=request.user, is_active=True)
            
            if not user_accounts.exists():
                return Response([], status=status.HTTP_200_OK)
            
            # Collect all labels from all accounts
            all_labels = {}  # label_id -> {"name": label_name, "unread_count": count}
            
            for account in user_accounts:
                try:
                    # Get all labels from Gmail
                    gmail_labels = GmailService.get_all_labels(account)
                    
                    # Initialize labels if not seen before
                    for label_id, label_name in gmail_labels.items():
                        if label_id not in all_labels:
                            all_labels[label_id] = {
                                "id": label_id,
                                "name": label_name,
                                "unread_count": 0
                            }
                    
                    # Count unread emails for each label
                    for label_id in gmail_labels.keys():
                        if connection.vendor == 'sqlite':
                            # SQLite JSON1: Check if label_id exists in the labels JSON array
                            unread_count = Email.objects.filter(
                                account=account,
                                is_read=False
                            ).extra(
                                where=["EXISTS (SELECT 1 FROM json_each(emails_email.labels) WHERE json_each.value = %s)"],
                                params=[label_id]
                            ).count()
                        else:
                            # PostgreSQL: use contains with array syntax
                            unread_count = Email.objects.filter(
                                account=account,
                                labels__contains=[label_id],
                                is_read=False
                            ).count()
                        all_labels[label_id]["unread_count"] += unread_count
                except Exception as e:
                    logger.error(f"Error fetching labels for account {account.email}: {e}", exc_info=True)
                    continue
            
            # Count uncategorized emails (emails with no user labels)
            # System labels like INBOX, SENT, etc. don't count as "categorization"
            system_label_ids = {"INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"}
            user_label_ids = [lid for lid in all_labels.keys() if lid not in system_label_ids]
            
            uncategorized_count = 0
            for account in user_accounts:
                # Get all unread emails for this account
                all_unread = Email.objects.filter(account=account, is_read=False)
                
                # Count emails that have no user labels
                # Use JSONField contains lookup to check if email has any user labels
                if user_label_ids:
                    # Emails that don't contain any user labels
                    uncategorized = all_unread.exclude(
                        Q(labels__overlap=user_label_ids)
                    )
                else:
                    # If no user labels exist, all unread emails are uncategorized
                    uncategorized = all_unread
                
                uncategorized_count += uncategorized.count()
            
            # Add uncategorized label if there are uncategorized emails
            if uncategorized_count > 0:
                all_labels["__UNCATEGORIZED__"] = {
                    "id": "__UNCATEGORIZED__",
                    "name": "Uncategorized",
                    "unread_count": uncategorized_count
                }
            
            # Convert to list and sort by name
            labels_list = list(all_labels.values())
            labels_list.sort(key=lambda x: x["name"])
            
            # Move "Uncategorized" to the end if it exists
            uncategorized = [l for l in labels_list if l["id"] == "__UNCATEGORIZED__"]
            if uncategorized:
                labels_list = [l for l in labels_list if l["id"] != "__UNCATEGORIZED__"] + uncategorized
            
            serializer = LabelSerializer(labels_list, many=True)
            return Response(serializer.data, status=status.HTTP_200_OK)
            
        except Exception as e:
            logger.error(f"Error fetching labels: {e}", exc_info=True)
            return Response(
                {"error": str(e)}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class LabelFiltersView(APIView):
    """Get all filters associated with a specific label"""
    permission_classes = [IsAuthenticated]

    def get(self, request, label_id):
        try:
            # Get all active email accounts for the user
            user_accounts = EmailAccount.objects.filter(user=request.user, is_active=True)
            
            if not user_accounts.exists():
                return Response([], status=status.HTTP_200_OK)
            
            # Get all filters from user's accounts that apply this label
            filters = Filter.objects.filter(
                account__in=user_accounts
            )
            
            # Filter to only those that have this label in their actions
            matching_filters = []
            for filter_obj in filters:
                # Check if this filter's actions include the label_id
                add_label_ids = filter_obj.actions.get("addLabelIds", [])
                if label_id in add_label_ids:
                    matching_filters.append(filter_obj)
            
            serializer = FilterSerializer(matching_filters, many=True)
            return Response(serializer.data, status=status.HTTP_200_OK)
            
        except Exception as e:
            logger.error(f"Error fetching filters for label {label_id}: {e}", exc_info=True)
            return Response(
                {"error": str(e)}, 
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# Keep function-based views for backward compatibility
logout = LogoutView.as_view()
user_detail = UserDetailView.as_view()
user_profile_update = UserProfileUpdateView.as_view()
