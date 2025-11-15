"""
Views for managing Gmail filters
"""
import logging
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
from .models import Filter, EmailAccount
from .gmail_service import GmailService
from .serializers import FilterSerializer

logger = logging.getLogger(__name__)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def create_filter(request):
    """Create a new Gmail filter"""
    try:
        account_id = request.data.get('account_id')
        if not account_id:
            return Response(
                {"error": "account_id is required"},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verify account belongs to user
        account = get_object_or_404(
            EmailAccount,
            id=account_id,
            user=request.user,
            is_active=True
        )
        
        criteria = request.data.get('criteria', {})
        actions = request.data.get('actions', {})
        
        # Create filter via Gmail API
        filter_data = {
            'criteria': criteria,
            'action': actions
        }
        
        gmail_filter = GmailService.create_filter(account, filter_data)
        
        # Sync to get the created filter
        GmailService.sync_filters(account)
        
        # Get the newly created filter from database
        filter_obj = Filter.objects.filter(
            account=account,
            gmail_filter_id=gmail_filter.get('id')
        ).first()
        
        if filter_obj:
            serializer = FilterSerializer(filter_obj)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        else:
            return Response(
                {"error": "Filter created but could not be retrieved"},
                status=status.HTTP_201_CREATED
            )
            
    except Exception as e:
        logger.error(f"Error creating filter: {e}", exc_info=True)
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['PUT'])
@permission_classes([IsAuthenticated])
def update_filter(request, filter_id):
    """Update a Gmail filter (delete old, create new)"""
    try:
        filter_obj = get_object_or_404(Filter, id=filter_id)
        
        # Verify account belongs to user
        if filter_obj.account.user != request.user:
            return Response(
                {"error": "Permission denied"},
                status=status.HTTP_403_FORBIDDEN
            )
        
        criteria = request.data.get('criteria', {})
        actions = request.data.get('actions', {})
        
        # Delete old filter
        GmailService.delete_filter(filter_obj.account, filter_obj.gmail_filter_id)
        
        # Create new filter with updated data
        filter_data = {
            'criteria': criteria,
            'action': actions
        }
        
        gmail_filter = GmailService.create_filter(filter_obj.account, filter_data)
        
        # Sync to get the updated filter
        GmailService.sync_filters(filter_obj.account)
        
        # Get the updated filter from database
        updated_filter = Filter.objects.filter(
            account=filter_obj.account,
            gmail_filter_id=gmail_filter.get('id')
        ).first()
        
        if updated_filter:
            serializer = FilterSerializer(updated_filter)
            return Response(serializer.data, status=status.HTTP_200_OK)
        else:
            return Response(
                {"error": "Filter updated but could not be retrieved"},
                status=status.HTTP_200_OK
            )
            
    except Exception as e:
        logger.error(f"Error updating filter: {e}", exc_info=True)
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def delete_filter(request, filter_id):
    """Delete a Gmail filter"""
    try:
        filter_obj = get_object_or_404(Filter, id=filter_id)
        
        # Verify account belongs to user
        if filter_obj.account.user != request.user:
            return Response(
                {"error": "Permission denied"},
                status=status.HTTP_403_FORBIDDEN
            )
        
        # Delete via Gmail API
        GmailService.delete_filter(filter_obj.account, filter_obj.gmail_filter_id)
        
        # Delete from database
        filter_obj.delete()
        
        return Response(status=status.HTTP_204_NO_CONTENT)
        
    except Exception as e:
        logger.error(f"Error deleting filter: {e}", exc_info=True)
        return Response(
            {"error": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )





