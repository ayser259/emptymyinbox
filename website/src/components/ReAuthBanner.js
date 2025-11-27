import React, { useState } from 'react';
import './ReAuthBanner.css';

function ReAuthBanner({ accountEmail, onReauthenticate, onDismiss }) {
  const [isLoading, setIsLoading] = useState(false);

  const handleReauthenticate = async () => {
    setIsLoading(true);
    try {
      await onReauthenticate();
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="reauth-banner">
      <div className="reauth-banner-content">
        <div className="reauth-banner-icon">⚠️</div>
        <div className="reauth-banner-message">
          <strong>Authentication Required</strong>
          <p>
            Your Gmail account ({accountEmail}) needs to be re-authenticated to continue syncing emails.
          </p>
        </div>
        <div className="reauth-banner-actions">
          <button
            className="btn-reauth"
            onClick={handleReauthenticate}
            disabled={isLoading}
          >
            {isLoading ? 'Connecting...' : 'Re-authenticate'}
          </button>
          {onDismiss && (
            <button
              className="btn-dismiss"
              onClick={onDismiss}
              disabled={isLoading}
            >
              Dismiss
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

export default ReAuthBanner;


