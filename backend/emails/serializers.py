from django.contrib.auth.models import User
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from .models import EmailAccount, Email


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
            "received_at",
            "account_email",
        ]


# Authentication Serializers
class UserRegistrationSerializer(serializers.ModelSerializer):
    """Serializer for user registration"""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ["username", "email", "password", "password_confirm", "first_name", "last_name"]

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError({"password": "Passwords do not match"})
        return attrs

    def create(self, validated_data):
        validated_data.pop("password_confirm")
        user = User.objects.create_user(
            username=validated_data["username"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
        )
        return user


class UserSerializer(serializers.ModelSerializer):
    """Serializer for user details"""
    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name", "date_joined"]
        read_only_fields = ["id", "date_joined"]



