"""
Celery tasks for background email syncing
Run with: celery -A backend worker --loglevel=info
"""
import logging
from celery import shared_task
from .models import EmailAccount
from .gmail_service import GmailService

logger = logging.getLogger(__name__)


@shared_task
def sync_all_accounts():
    """Sync emails for all active accounts"""
    accounts = EmailAccount.objects.filter(is_active=True)
    for account in accounts:
        try:
            GmailService.sync_emails(account, max_results=50)
        except Exception as e:
            logger.error(f"Error syncing account {account.email}: {e}", exc_info=True)


@shared_task
def sync_account(account_id):
    """Sync emails for a specific account"""
    try:
        account = EmailAccount.objects.get(id=account_id, is_active=True)
        GmailService.sync_emails(account, max_results=100)
    except EmailAccount.DoesNotExist:
        logger.warning(f"Account {account_id} not found")
    except Exception as e:
        logger.error(f"Error syncing account {account_id}: {e}", exc_info=True)
