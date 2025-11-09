import React, { useState, useEffect } from 'react';
import api from '../services/api';
import './EmailAccountList.css';

function EmailAccountList({ onAccountSelect, selectedAccountId }) {
  const [accounts, setAccounts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [connecting, setConnecting] = useState(false);

  useEffect(() => {
    loadAccounts();
  }, []);

  const loadAccounts = async () => {
    try {
      setLoading(true);
      const data = await api.getAccounts();
      setAccounts(data);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleConnectGmail = async () => {
    try {
      setConnecting(true);
      const authUrl = await api.addGmailAccount();
      // Redirect to Gmail OAuth
      window.location.href = authUrl;
    } catch (err) {
      setError(err.message);
      setConnecting(false);
    }
  };

  const handleSync = async (accountId, e) => {
    e.stopPropagation();
    try {
      await api.syncAccount(accountId);
      await loadAccounts();
    } catch (err) {
      alert(`Sync failed: ${err.message}`);
    }
  };

  if (loading) {
    return <div className="email-account-list loading">Loading accounts...</div>;
  }

  return (
    <div className="email-account-list">
      <div className="account-list-header">
        <h2>Email Accounts</h2>
        <button 
          onClick={handleConnectGmail} 
          disabled={connecting}
          className="btn-connect"
        >
          {connecting ? 'Connecting...' : '+ Connect Gmail'}
        </button>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="accounts">
        {accounts.length === 0 ? (
          <div className="empty-state">
            <p>No email accounts connected yet.</p>
            <p>Click "Connect Gmail" to get started!</p>
          </div>
        ) : (
          accounts.map((account) => (
            <div
              key={account.id}
              className={`account-item ${selectedAccountId === account.id ? 'selected' : ''}`}
              onClick={() => onAccountSelect(account.id)}
            >
              <div className="account-info">
                <div className="account-email">{account.email}</div>
                <div className="account-meta">
                  {account.email_count} emails
                  {account.last_sync && (
                    <span> • Last synced: {new Date(account.last_sync).toLocaleString()}</span>
                  )}
                </div>
              </div>
              <button
                onClick={(e) => handleSync(account.id, e)}
                className="btn-sync"
                title="Sync emails"
              >
                ↻
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default EmailAccountList;






