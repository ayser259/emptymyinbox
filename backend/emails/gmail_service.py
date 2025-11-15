import base64
import logging
from datetime import timedelta
from email.utils import parsedate_to_datetime
from typing import List, Dict, Optional

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from django.conf import settings
from django.utils import timezone

from .models import EmailAccount, Email, Filter

logger = logging.getLogger(__name__)

# Gmail API scopes
SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.settings.basic",  # For filter management
]


class GmailService:
    """Service class for interacting with Gmail API"""

    @staticmethod
    def get_authorization_url(redirect_uri: Optional[str] = None, state: Optional[str] = None):
        """Get OAuth2 authorization URL for Gmail"""
        redirect_uri = redirect_uri or settings.GMAIL_REDIRECT_URI
        flow = Flow.from_client_config(
            {
                "web": {
                    "client_id": settings.GMAIL_CLIENT_ID,
                    "client_secret": settings.GMAIL_CLIENT_SECRET,
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                    "redirect_uris": [redirect_uri],
                }
            },
            scopes=SCOPES,
            redirect_uri=redirect_uri,
        )
        authorization_url, generated_state = flow.authorization_url(
            access_type="offline",
            include_granted_scopes="true",
            prompt="consent select_account",
            state=state,
        )
        # google-auth will return the explicitly provided state value as generated_state
        return authorization_url, generated_state

    @staticmethod
    def exchange_code_for_tokens(code: str, redirect_uri: Optional[str] = None):
        """Exchange authorization code for access and refresh tokens"""
        redirect_uri = redirect_uri or settings.GMAIL_REDIRECT_URI
        flow = Flow.from_client_config(
            {
                "web": {
                    "client_id": settings.GMAIL_CLIENT_ID,
                    "client_secret": settings.GMAIL_CLIENT_SECRET,
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                    "redirect_uris": [redirect_uri],
                }
            },
            scopes=SCOPES,
            redirect_uri=redirect_uri,
        )
        flow.fetch_token(code=code)
        credentials = flow.credentials
        
        # Ensure token_expiry is timezone-aware
        expiry = credentials.expiry
        if expiry and expiry.tzinfo is None:
            expiry = timezone.make_aware(expiry)
        
        return {
            "access_token": credentials.token,
            "refresh_token": credentials.refresh_token,
            "token_expiry": expiry,
        }

    @staticmethod
    def get_credentials(email_account: EmailAccount) -> Credentials:
        """Get valid credentials for an email account, refreshing if needed"""
        credentials = Credentials(
            token=email_account.access_token,
            refresh_token=email_account.refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=settings.GMAIL_CLIENT_ID,
            client_secret=settings.GMAIL_CLIENT_SECRET,
        )

        # Refresh token if expired or about to expire
        # Ensure token_expiry is timezone-aware for comparison
        token_expiry = email_account.token_expiry
        if token_expiry and token_expiry.tzinfo is None:
            token_expiry = timezone.make_aware(token_expiry)
        
        should_refresh = credentials.expired
        if not should_refresh and token_expiry:
            # Compare with timezone-aware datetime
            should_refresh = token_expiry <= timezone.now() + timedelta(minutes=5)
        
        if should_refresh:
            credentials.refresh(Request())
            email_account.access_token = credentials.token
            if credentials.refresh_token:
                email_account.refresh_token = credentials.refresh_token
            
            # Ensure expiry is timezone-aware before saving
            expiry = credentials.expiry
            if expiry and expiry.tzinfo is None:
                expiry = timezone.make_aware(expiry)
            email_account.token_expiry = expiry
            email_account.save()

        return credentials

    @staticmethod
    def get_service(email_account: EmailAccount):
        """Get Gmail API service instance"""
        credentials = GmailService.get_credentials(email_account)
        return build("gmail", "v1", credentials=credentials)

    @staticmethod
    def get_user_email(email_account: EmailAccount) -> str:
        """Get the email address associated with the account"""
        service = GmailService.get_service(email_account)
        profile = service.users().getProfile(userId="me").execute()
        return profile.get("emailAddress", "")

    @staticmethod
    def parse_email_message(message_data: Dict) -> Dict:
        """Parse Gmail API message format into our Email model format"""
        payload = message_data.get("payload", {})
        headers = payload.get("headers", [])

        # Extract headers
        header_dict = {h["name"].lower(): h["value"] for h in headers}
        subject = header_dict.get("subject", "")
        sender = header_dict.get("from", "")
        sender_name = sender.split("<")[0].strip().strip('"') if "<" in sender else sender
        sender_email = (
            sender.split("<")[1].strip(">") if "<" in sender else sender
        )

        # Parse recipients
        recipients_to = header_dict.get("to", "")
        recipients_cc = header_dict.get("cc", "")
        recipients_bcc = header_dict.get("bcc", "")

        # Parse date
        date_str = header_dict.get("date", "")
        try:
            received_at = parsedate_to_datetime(date_str)
            if received_at.tzinfo is None:
                received_at = timezone.make_aware(received_at)
        except (ValueError, TypeError) as e:
            logger.warning(f"Failed to parse email date '{date_str}': {e}. Using current time.")
            received_at = timezone.now()

        # Extract body
        body_text = ""
        body_html = ""
        snippet = message_data.get("snippet", "")

        def extract_body(part):
            """Recursively extract body from message parts"""
            nonlocal body_text, body_html
            if part.get("mimeType") == "text/plain":
                data = part.get("body", {}).get("data", "")
                if data:
                    body_text = base64.urlsafe_b64decode(data).decode("utf-8", errors="ignore")
            elif part.get("mimeType") == "text/html":
                data = part.get("body", {}).get("data", "")
                if data:
                    body_html = base64.urlsafe_b64decode(data).decode("utf-8", errors="ignore")
            elif part.get("parts"):
                for subpart in part.get("parts", []):
                    extract_body(subpart)

        extract_body(payload)

        # Extract labels
        labels = message_data.get("labelIds", [])

        return {
            "gmail_id": message_data.get("id"),
            "thread_id": message_data.get("threadId"),
            "subject": subject,
            "sender": sender_email,
            "sender_name": sender_name,
            "recipients_to": recipients_to,
            "recipients_cc": recipients_cc,
            "recipients_bcc": recipients_bcc,
            "body_text": body_text,
            "body_html": body_html,
            "snippet": snippet,
            "is_read": "UNREAD" not in labels,
            "is_starred": "STARRED" in labels,
            "labels": labels,
            "received_at": received_at,
        }

    @staticmethod
    def sync_emails(email_account: EmailAccount, max_results: int = 50):
        """Sync emails from Gmail for an account"""
        try:
            service = GmailService.get_service(email_account)
            synced_count = 0

            # Get list of recent messages
            results = (
                service.users()
                .messages()
                .list(userId="me", maxResults=max_results, q="is:unread")
                .execute()
            )
            messages = results.get("messages", [])

            for msg in messages:
                try:
                    # Get full message details
                    message = (
                        service.users()
                        .messages()
                        .get(userId="me", id=msg["id"], format="full")
                        .execute()
                    )

                    # Parse message
                    email_data = GmailService.parse_email_message(message)

                    # Create or update email in database
                    email_obj, created = Email.objects.update_or_create(
                        account=email_account,
                        gmail_id=email_data["gmail_id"],
                        defaults=email_data,
                    )
                    # Always update labels even for existing emails to ensure they're current
                    # This is important because labels can change in Gmail
                    if not created:
                        email_obj.labels = email_data.get("labels", [])
                        email_obj.save(update_fields=["labels"])
                    if created:
                        synced_count += 1
                except Exception as e:
                    logger.error(f"Error syncing message {msg['id']}: {e}", exc_info=True)
                    continue

            # Also sync all starred emails
            starred_count = GmailService.sync_starred_emails(email_account)
            synced_count += starred_count

            # Update last sync time
            email_account.last_sync = timezone.now()
            email_account.save()

            return synced_count
        except HttpError as error:
            logger.error(f"An error occurred syncing emails for account {email_account.email}: {error}", exc_info=True)
            raise

    @staticmethod
    def sync_starred_emails(email_account: EmailAccount, max_results: int = 500):
        """Sync all starred emails from Gmail for an account"""
        try:
            service = GmailService.get_service(email_account)

            # Get all starred messages
            results = (
                service.users()
                .messages()
                .list(userId="me", q="is:starred", maxResults=max_results)
                .execute()
            )
            messages = results.get("messages", [])

            synced_count = 0
            for msg in messages:
                try:
                    # Get full message details
                    message = (
                        service.users()
                        .messages()
                        .get(userId="me", id=msg["id"], format="full")
                        .execute()
                    )

                    # Parse message
                    email_data = GmailService.parse_email_message(message)

                    # Create or update email in database (ensuring is_starred is set)
                    email_data["is_starred"] = True  # Ensure starred flag is set
                    email_obj, created = Email.objects.update_or_create(
                        account=email_account,
                        gmail_id=email_data["gmail_id"],
                        defaults=email_data,
                    )
                    # Always update labels even for existing emails
                    if not created:
                        email_obj.labels = email_data.get("labels", [])
                        email_obj.is_starred = True
                        email_obj.save(update_fields=["labels", "is_starred"])
                    if created:
                        synced_count += 1
                except Exception as e:
                    logger.error(f"Error syncing starred message {msg['id']}: {e}", exc_info=True)
                    continue

            return synced_count
        except HttpError as error:
            logger.error(f"An error occurred syncing starred emails for account {email_account.email}: {error}", exc_info=True)
            # Don't raise - starred sync failure shouldn't break regular sync
            return 0

    @staticmethod
    def modify_email_labels(email_account: EmailAccount, gmail_id: str, add_labels: List[str] = None, remove_labels: List[str] = None):
        """Modify labels on a Gmail message"""
        try:
            service = GmailService.get_service(email_account)
            
            body = {}
            if add_labels:
                body["addLabelIds"] = add_labels
            if remove_labels:
                body["removeLabelIds"] = remove_labels
            
            if not body:
                return
            
            result = (
                service.users()
                .messages()
                .modify(userId="me", id=gmail_id, body=body)
                .execute()
            )
            return result
        except HttpError as error:
            logger.error(f"An error occurred modifying labels for message {gmail_id}: {error}", exc_info=True)
            raise

    @staticmethod
    def get_all_labels(email_account: EmailAccount) -> Dict[str, str]:
        """Get all Gmail labels for an account, returning a dict of label_id -> label_name"""
        try:
            service = GmailService.get_service(email_account)
            results = service.users().labels().list(userId="me").execute()
            labels = results.get("labels", [])
            
            # Return dict of label_id -> label_name
            # Filter out system labels that we don't want to show
            system_labels = {"INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "UNREAD", "STARRED", "IMPORTANT"}
            label_dict = {}
            for label in labels:
                label_id = label.get("id")
                label_name = label.get("name")
                label_type = label.get("type", "user")  # "user" or "system"
                
                # Only include user labels and some system labels
                if label_type == "user" or label_id in system_labels:
                    label_dict[label_id] = label_name
            
            return label_dict
        except HttpError as error:
            logger.error(f"An error occurred fetching labels for account {email_account.email}: {error}", exc_info=True)
            raise

    @staticmethod
    def get_all_filters(email_account: EmailAccount) -> List[Dict]:
        """Get all Gmail filters for an account"""
        try:
            service = GmailService.get_service(email_account)
            results = service.users().settings().filters().list(userId="me").execute()
            filters = results.get("filter", [])
            return filters
        except HttpError as error:
            logger.error(f"An error occurred fetching filters for account {email_account.email}: {error}", exc_info=True)
            raise

    @staticmethod
    def sync_filters(email_account: EmailAccount) -> int:
        """Sync filters from Gmail for an account"""
        try:
            gmail_filters = GmailService.get_all_filters(email_account)
            synced_count = 0
            
            for filter_data in gmail_filters:
                gmail_filter_id = filter_data.get("id")
                criteria = filter_data.get("criteria", {})
                action = filter_data.get("action", {})
                
                # Create or update filter in database
                Filter.objects.update_or_create(
                    account=email_account,
                    gmail_filter_id=gmail_filter_id,
                    defaults={
                        "criteria": criteria,
                        "actions": action,
                    }
                )
                synced_count += 1
            
            return synced_count
        except HttpError as error:
            logger.error(f"An error occurred syncing filters for account {email_account.email}: {error}", exc_info=True)
            raise

    @staticmethod
    def create_filter(email_account: EmailAccount, filter_data: Dict) -> Dict:
        """Create a new Gmail filter"""
        try:
            service = GmailService.get_service(email_account)
            result = service.users().settings().filters().create(
                userId="me",
                body=filter_data
            ).execute()
            return result
        except HttpError as error:
            logger.error(f"An error occurred creating filter for account {email_account.email}: {error}", exc_info=True)
            raise

    @staticmethod
    def delete_filter(email_account: EmailAccount, filter_id: str):
        """Delete a Gmail filter"""
        try:
            service = GmailService.get_service(email_account)
            service.users().settings().filters().delete(
                userId="me",
                id=filter_id
            ).execute()
        except HttpError as error:
            logger.error(f"An error occurred deleting filter {filter_id} for account {email_account.email}: {error}", exc_info=True)
            raise

