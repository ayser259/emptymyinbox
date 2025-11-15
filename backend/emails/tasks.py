"""
Celery tasks for background email syncing
Run with: celery -A backend worker --loglevel=info
"""
import logging
from celery import shared_task
from .models import EmailAccount
from .gmail_service import GmailService

logger = logging.getLogger(__name__)


@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def sync_all_accounts(self, max_results=50):
    """Sync emails for all active accounts"""
    accounts = EmailAccount.objects.filter(is_active=True)
    for account in accounts:
        sync_account.delay(account.id, max_results=max_results)


@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def sync_account(self, account_id, max_results=100, include_filters=False):
    """Sync emails for a specific account"""
    try:
        account = EmailAccount.objects.get(id=account_id, is_active=True)
    except EmailAccount.DoesNotExist:
        logger.warning(f"Account {account_id} not found")
        return

    try:
        GmailService.sync_emails(account, max_results=max_results)

        if include_filters:
            try:
                GmailService.sync_filters(account)
            except Exception as filters_error:
                logger.warning(
                    f"Filter sync failed for account {account.email}: {filters_error}",
                    exc_info=True,
                )
    except Exception as e:
        logger.error(f"Error syncing account {account_id}: {e}", exc_info=True)
