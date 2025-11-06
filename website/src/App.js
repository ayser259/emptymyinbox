import React, { useState, useEffect } from 'react';
import EmailAccountList from './components/EmailAccountList';
import EmailList from './components/EmailList';
import Login from './components/Login';
import Signup from './components/Signup';
import api from './services/api';
import './App.css';

function App() {
  const [selectedAccountId, setSelectedAccountId] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [showSignup, setShowSignup] = useState(false);
  const [user, setUser] = useState(null);

  // Check authentication status on mount
  useEffect(() => {
    checkAuth();
    
    // Check if we're returning from Gmail OAuth callback
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('account_connected') === 'true') {
      // Account was successfully connected, refresh to show it
      window.location.href = window.location.pathname;
    }
  }, []);

  const checkAuth = async () => {
    try {
      const userData = await api.getUser();
      setUser(userData);
      setIsAuthenticated(true);
    } catch (error) {
      setIsAuthenticated(false);
      api.clearTokens();
    } finally {
      setIsLoading(false);
    }
  };

  const handleLogin = async (credentials) => {
    try {
      const response = await api.login(credentials);
      setUser(response.user);
      setIsAuthenticated(true);
    } catch (error) {
      throw error; // Re-throw so Login component can display it
    }
  };

  const handleSignup = async (userData) => {
    const response = await api.register(userData);
    setUser(response.user);
    setIsAuthenticated(true);
  };

  const handleLogout = async () => {
    await api.logout();
    setIsAuthenticated(false);
    setUser(null);
    setSelectedAccountId(null);
  };

  if (isLoading) {
    return (
      <div className="App">
        <div className="loading-container">
          <div className="loading-spinner"></div>
          <p>Loading...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return showSignup ? (
      <Signup onSignup={handleSignup} switchToLogin={() => setShowSignup(false)} />
    ) : (
      <Login onLogin={handleLogin} switchToSignup={() => setShowSignup(true)} />
    );
  }

  return (
    <div className="App">
      <div className="app-header">
        <div className="header-left">
          <img src="/images/logo128.png" alt="Empty My Inbox" className="app-logo" />
          <h1>Empty My Inbox</h1>
        </div>
        <div className="header-actions">
          {user && (
            <span className="user-info">
              {user.first_name || user.username}
            </span>
          )}
          <button className="btn-logout" onClick={handleLogout}>
            Logout
          </button>
        </div>
      </div>
      <div className="app-content">
        <EmailAccountList
          onAccountSelect={setSelectedAccountId}
          selectedAccountId={selectedAccountId}
        />
        <EmailList accountId={selectedAccountId} />
      </div>
    </div>
  );
}

export default App;
