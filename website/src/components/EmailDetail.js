import React from 'react';
import './EmailDetail.css';

function EmailDetail({ email, onClose }) {
  const formatFullDate = (dateString) => {
    return new Date(dateString).toLocaleString([], {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  return (
    <div className="email-detail">
      <div className="email-detail-header">
        <button onClick={onClose} className="btn-close">
          ×
        </button>
      </div>
      <div className="email-detail-content">
        <div className="email-detail-subject">{email.subject || '(No subject)'}</div>
        <div className="email-detail-meta">
          <div className="email-detail-from">
            <strong>From:</strong> {email.sender_name || email.sender} &lt;{email.sender}&gt;
          </div>
          {email.recipients_to && (
            <div className="email-detail-to">
              <strong>To:</strong> {email.recipients_to}
            </div>
          )}
          <div className="email-detail-date">
            {formatFullDate(email.received_at)}
          </div>
        </div>
        <div className="email-detail-body">
          {email.body_html ? (
            <div
              dangerouslySetInnerHTML={{ __html: email.body_html }}
              className="email-body-html"
            />
          ) : (
            <div className="email-body-text">
              {email.body_text || email.snippet}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default EmailDetail;






