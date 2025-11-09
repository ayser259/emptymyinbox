from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    EmailAccountViewSet,
    EmailViewSet,
    gmail_auth_start,
    gmail_auth_callback,
    register,
    login,
    logout,
    user_detail,
    user_profile_update,
    LabelsView,
    LabelFiltersView,
)
from .filter_views import create_filter, update_filter, delete_filter

router = DefaultRouter()
router.register(r"accounts", EmailAccountViewSet, basename="emailaccount")
router.register(r"emails", EmailViewSet, basename="email")

urlpatterns = [
    path("", include(router.urls)),
    # Authentication endpoints
    path("auth/register/", register, name="register"),
    path("auth/login/", login, name="login"),
    path("auth/logout/", logout, name="logout"),
    path("auth/user/", user_detail, name="user-detail"),
    path("auth/profile/", user_profile_update, name="user-profile-update"),
    path("auth/token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    # Gmail OAuth endpoints
    path("auth/gmail/start/", gmail_auth_start, name="gmail-auth-start"),
    path("auth/gmail/callback/", gmail_auth_callback, name="gmail-auth-callback"),
    # Labels endpoint
    path("labels/", LabelsView.as_view(), name="labels"),
    path("labels/<str:label_id>/filters/", LabelFiltersView.as_view(), name="label-filters"),
    # Filter management endpoints
    path("filters/", create_filter, name="create-filter"),
    path("filters/<int:filter_id>/", update_filter, name="update-filter"),
    path("filters/<int:filter_id>/delete/", delete_filter, name="delete-filter"),
]



