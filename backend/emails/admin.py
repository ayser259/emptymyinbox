from django.contrib import admin
from .models import EmailAccount, Email


@admin.register(EmailAccount)
class EmailAccountAdmin(admin.ModelAdmin):
    list_display = ["email", "user", "is_active", "last_sync", "created_at"]
    list_filter = ["is_active", "created_at"]
    search_fields = ["email", "user__username"]


@admin.register(Email)
class EmailAdmin(admin.ModelAdmin):
    list_display = ["subject", "sender", "account", "is_read", "received_at"]
    list_filter = ["is_read", "is_starred", "account", "received_at"]
    search_fields = ["subject", "sender", "body_text"]
    readonly_fields = ["gmail_id", "thread_id", "created_at", "updated_at"]
