from datetime import timedelta

from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
from django.db.models import UniqueConstraint


class EmailAccount(models.Model):
    """Represents a Gmail account connected to the app"""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="email_accounts")
    email = models.EmailField()
    access_token = models.TextField()
    refresh_token = models.TextField(null=True, blank=True)
    token_expiry = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    last_sync = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            UniqueConstraint(fields=["user", "email"], name="unique_user_email")
        ]
        indexes = [
            models.Index(fields=["user", "is_active"]),
        ]

    def __str__(self):
        return f"{self.email} ({self.user.username})"


class Email(models.Model):
    """Represents an email message from Gmail"""
    account = models.ForeignKey(EmailAccount, on_delete=models.CASCADE, related_name="emails")
    gmail_id = models.CharField(max_length=255, db_index=True)
    thread_id = models.CharField(max_length=255, db_index=True)
    subject = models.TextField(blank=True)
    sender = models.EmailField()
    sender_name = models.CharField(max_length=255, blank=True)
    recipients_to = models.TextField(blank=True)  # JSON array
    recipients_cc = models.TextField(blank=True)  # JSON array
    recipients_bcc = models.TextField(blank=True)  # JSON array
    body_text = models.TextField(blank=True)
    body_html = models.TextField(blank=True)
    snippet = models.TextField(blank=True)
    is_read = models.BooleanField(default=False)
    is_starred = models.BooleanField(default=False)
    labels = models.JSONField(default=list)  # List of label IDs
    received_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-received_at"]
        constraints = [
            UniqueConstraint(fields=["account", "gmail_id"], name="unique_account_gmail_id")
        ]
        indexes = [
            models.Index(fields=["account", "is_read"]),
            models.Index(fields=["account", "received_at"]),
        ]

    def __str__(self):
        return f"{self.subject[:50]} - {self.sender}"


class UserProfile(models.Model):
    """Extended user profile with additional information"""
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    state = models.CharField(max_length=100, blank=True)
    zip_code = models.CharField(max_length=20, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username}'s Profile"


class Filter(models.Model):
    """Represents a Gmail filter rule"""
    account = models.ForeignKey(EmailAccount, on_delete=models.CASCADE, related_name="filters")
    gmail_filter_id = models.CharField(max_length=255, db_index=True)  # Gmail's filter ID
    criteria = models.JSONField(default=dict)  # Filter criteria (from, subject, hasAttachment, etc.)
    actions = models.JSONField(default=dict)  # Filter actions (addLabelIds, removeLabelIds, etc.)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            UniqueConstraint(fields=["account", "gmail_filter_id"], name="unique_account_filter_id")
        ]
        indexes = [
            models.Index(fields=["account"]),
        ]

    def __str__(self):
        # Try to create a readable description
        criteria_parts = []
        if self.criteria.get("from"):
            criteria_parts.append(f"from: {self.criteria['from']}")
        if self.criteria.get("subject"):
            criteria_parts.append(f"subject: {self.criteria['subject']}")
        if self.criteria.get("hasAttachment"):
            criteria_parts.append("has attachment")
        
        criteria_str = ", ".join(criteria_parts) if criteria_parts else "no criteria"
        return f"Filter: {criteria_str}"


class GmailOAuthState(models.Model):
    """Tracks in-flight Gmail OAuth sessions for clients without shared cookies"""
    state = models.CharField(max_length=255, unique=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="gmail_oauth_states")
    redirect_uri = models.CharField(max_length=512, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["state"]),
        ]

    def is_expired(self, ttl: timedelta) -> bool:
        return self.created_at < timezone.now() - ttl
