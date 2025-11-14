//
//  GmailWatchManager.swift
//  emptyMyInbox
//
//  High-level guidance for adding Gmail Pub/Sub notifications
//

enum GmailWatchManager {
    
    /// Steps to turn on Gmail push notifications without polling Gmail from the app.
    static let implementationNotes: String = """
    1. Google Cloud setup
       - Enable Pub/Sub API in the same project as the Gmail OAuth client.
       - Create a Pub/Sub topic, e.g. projects/<project>/topics/gmail-notifications.
       - Create a subscription for that topic (push to Cloud Run/Function or pull via worker).
       - Grant `gmail-api-push@system.gserviceaccount.com` the `Pub/Sub Publisher` role on that topic.

    2. Backend watch endpoints
       - After a user connects Gmail, call `users.watch` with:
            topicName: your Pub/Sub topic
            labelIds: ["INBOX"] (optional filter)
            labelFilterAction: "include"
       - Persist the returned historyId per account; Gmail requires it for incremental sync.
       - Renew each watch at least every 7 days (the watch expires).

    3. Pub/Sub subscriber
       - Run an always-on process (Cloud Run min instance, Render worker, etc.) subscribed to the topic.
       - Each message contains `emailAddress` and `historyId`.
       - Use the stored refresh token to call `users.history.list` with `startHistoryId`.
       - Pull the new messages (if any) and update your database.
       - Update `startHistoryId` to the latest value returned.

    4. Push to devices
       - Once the backend stores the new email, send an APNs push via your server.
       - The client fetches the message details from your API when the user opens the notification.

    5. iOS plumbing
       - Register for remote notifications (APNs) and handle device tokens.
       - Provide an endpoint to store device tokens per user/account.
       - When a push is received, optionally show the summary and deep link to the message.

    With this setup the iOS app never polls Gmail directly; Gmail notifies your backend, and your backend
    does the incremental sync plus APNs push, minimizing quota usage.
    """
}

