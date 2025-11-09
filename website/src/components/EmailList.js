import React, { useState, useEffect } from 'react';
import api from '../services/api';
import EmailDetail from './EmailDetail';
import './EmailList.css';

function EmailList({ accountId }) {
  const [emails, setEmails] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedEmail, setSelectedEmail] = useState(null);
  const [filter, setFilter] = useState('all'); // all, unread, read

  useEffect(() => {
    if (accountId) {
      loadEmails();
    } else {
      setEmails([]);
      setSelectedEmail(null);
    }
  }, [accountId, filter]);

  const loadEmails = async () => {
    try {
      setLoading(true);
      const params = { account: accountId };
      if (filter === 'unread') {
        params.is_read = 'false';
      } else if (filter === 'read') {
        params.is_read = 'true';
      }
      const data = await api.getEmails(params);
      setEmails(data);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleEmailClick = async (email) => {
    try {
      const fullEmail = await api.getEmail(email.id);
      setSelectedEmail(fullEmail);
    } catch (err) {
      alert(`Failed to load email: ${err.message}`);
    }
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now - date;
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (days === 1) {
      return 'Yesterday';
    } else if (days < 7) {
      return date.toLocaleDateString([], { weekday: 'short' });
    } else {
      return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
    }
  };

  if (!accountId) {
    return (
      <div className="email-list-container empty">
        <div className="empty-state">
          <h3>Select an email account to view emails</h3>
        </div>
      </div>
    );
  }

  return (
    <div className="email-list-container">
      <div className="email-list">
        <div className="email-list-header">
          <h2>Inbox</h2>
          <div className="filters">
            <button
              className={filter === 'all' ? 'active' : ''}
              onClick={() => setFilter('all')}
            >
              All
            </button>
            <button
              className={filter === 'unread' ? 'active' : ''}
              onClick={() => setFilter('unread')}
            >
              Unread
            </button>
            <button
              className={filter === 'read' ? 'active' : ''}
              onClick={() => setFilter('read')}
            >
              Read
            </button>
          </div>
        </div>

        {error && <div className="error">{error}</div>}

        {loading ? (
          <div className="loading">Loading emails...</div>
        ) : emails.length === 0 ? (
          <div className="empty-state">
            <p>No emails found.</p>
            <p>Try syncing your account or check back later.</p>
          </div>
        ) : (
          <div className="emails">
            {emails.map((email) => (
              <div
                key={email.id}
                className={`email-item ${!email.is_read ? 'unread' : ''} ${
                  selectedEmail?.id === email.id ? 'selected' : ''
                }`}
                onClick={() => handleEmailClick(email)}
              >
                <div className="email-item-header">
                  <div className="email-sender">
                    {email.sender_name || email.sender}
                  </div>
                  <div className="email-date">{formatDate(email.received_at)}</div>
                </div>
                <div className="email-subject">{email.subject || '(No subject)'}</div>
                <div className="email-snippet">{email.snippet}</div>
                {email.is_starred && <span className="star">★</span>}
              </div>
            ))}
          </div>
        )}
      </div>

      {selectedEmail && (
        <EmailDetail
          email={selectedEmail}
          onClose={() => setSelectedEmail(null)}
        />
      )}
    </div>
  );
}

export default EmailList;







