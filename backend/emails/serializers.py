from django.contrib.auth.models import User
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from .models import EmailAccount, Email, UserProfile, Filter


class EmailAccountSerializer(serializers.ModelSerializer):
    email_count = serializers.SerializerMethodField()

    class Meta:
        model = EmailAccount
        fields = [
            "id",
            "email",
            "is_active",
            "last_sync",
            "created_at",
            "email_count",
        ]
        read_only_fields = ["id", "created_at", "last_sync"]

    def get_email_count(self, obj):
        return obj.emails.count()


class EmailSerializer(serializers.ModelSerializer):
    account_email = serializers.EmailField(source="account.email", read_only=True)

    class Meta:
        model = Email
        fields = [
            "id",
            "gmail_id",
            "thread_id",
            "subject",
            "sender",
            "sender_name",
            "recipients_to",
            "recipients_cc",
            "recipients_bcc",
            "body_text",
            "body_html",
            "snippet",
            "is_read",
            "is_starred",
            "labels",
            "received_at",
            "account_email",
            "created_at",
        ]
        read_only_fields = ["id", "created_at", "received_at"]


class EmailListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for email list views"""
    account_email = serializers.EmailField(source="account.email", read_only=True)

    class Meta:
        model = Email
        fields = [
            "id",
            "gmail_id",
            "subject",
            "sender",
            "sender_name",
            "snippet",
            "is_read",
            "is_starred",
            "labels",
            "received_at",
            "account_email",
        ]


# Authentication Serializers
class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for user profile"""
    class Meta:
        model = UserProfile
        fields = ["state", "zip_code"]
        read_only_fields = ["created_at", "updated_at"]


class UserRegistrationSerializer(serializers.ModelSerializer):
    """Serializer for user registration"""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True, min_length=8)
    state = serializers.CharField(write_only=True, required=False, allow_blank=True)
    zip_code = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = ["username", "email", "password", "password_confirm", "first_name", "last_name", "state", "zip_code"]

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError({"password": "Passwords do not match"})
        return attrs

    def create(self, validated_data):
        state = validated_data.pop("state", "")
        zip_code = validated_data.pop("zip_code", "")
        validated_data.pop("password_confirm")
        user = User.objects.create_user(
            username=validated_data["username"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
        )
        # Create or update profile
        UserProfile.objects.update_or_create(
            user=user,
            defaults={"state": state, "zip_code": zip_code}
        )
        return user


class UserSerializer(serializers.ModelSerializer):
    """Serializer for user details"""
    profile = UserProfileSerializer(read_only=True, allow_null=True)
    state = serializers.SerializerMethodField()
    zip_code = serializers.SerializerMethodField()
    
    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name", "date_joined", "state", "zip_code", "profile"]
        read_only_fields = ["id", "date_joined"]
    
    def get_state(self, obj):
        try:
            return obj.profile.state if hasattr(obj, 'profile') and obj.profile else None
        except:
            return None
    
    def get_zip_code(self, obj):
        try:
            return obj.profile.zip_code if hasattr(obj, 'profile') and obj.profile else None
        except:
            return None


class LabelSerializer(serializers.Serializer):
    """Serializer for Gmail labels with unread counts"""
    id = serializers.CharField()
    name = serializers.CharField()
    unread_count = serializers.IntegerField()


class FilterSerializer(serializers.ModelSerializer):
    """Serializer for Gmail filters"""
    class Meta:
        model = Filter
        fields = [
            "id",
            "gmail_filter_id",
            "criteria",
            "actions",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]



