import Testing
@testable import EmptyMyInboxShared

struct ReplyRecipientResolverTests {

    @Test("Reply mode uses Reply-To when present")
    func replyUsesReplyTo() {
        let headers: [String: String] = [
            "from": "Sender <sender@example.com>",
            "reply-to": "Support <support@example.com>",
            "to": "me@mycompany.com",
            "cc": "cc@example.com",
            "subject": "Hello"
        ]
        let set = ReplyRecipientResolver.resolve(
            headers: headers,
            accountEmail: "me@mycompany.com",
            mode: .reply
        )
        #expect(set.to.count == 1)
        #expect(set.to[0].email == "support@example.com")
        #expect(set.cc.isEmpty)
    }

    @Test("Reply all excludes self and moves others to To/Cc")
    func replyAllExcludesSelf() {
        let headers: [String: String] = [
            "from": "Alice <alice@example.com>",
            "to": "me@mycompany.com, Bob <bob@example.com>",
            "cc": "Carol <carol@example.com>",
            "subject": "Team update"
        ]
        let set = ReplyRecipientResolver.resolve(
            headers: headers,
            accountEmail: "me@mycompany.com",
            mode: .replyAll
        )
        let emails = Set(set.to.map { $0.email.lowercased() } + set.cc.map { $0.email.lowercased() })
        #expect(!emails.contains("me@mycompany.com"))
        #expect(emails.contains("alice@example.com"))
        #expect(emails.contains("bob@example.com"))
        #expect(emails.contains("carol@example.com"))
    }

    @Test("Parses comma-separated addresses with display names")
    func parseMultipleAddresses() {
        let list = ReplyRecipientResolver.parseAddresses(
            from: "Alice <alice@example.com>, bob@example.com"
        )
        #expect(list.count == 2)
        #expect(list[0].email == "alice@example.com")
        #expect(list[0].displayName == "Alice")
        #expect(list[1].email == "bob@example.com")
    }

    @Test("Reply all is not meaningful for a single-party thread")
    func replyAllNotMeaningfulForSingleRecipient() {
        let headers: [String: String] = [
            "from": "Alice <alice@example.com>",
            "to": "me@mycompany.com",
            "subject": "Hello"
        ]
        let reply = ReplyRecipientResolver.resolve(
            headers: headers,
            accountEmail: "me@mycompany.com",
            mode: .reply
        )
        let replyAll = ReplyRecipientResolver.resolve(
            headers: headers,
            accountEmail: "me@mycompany.com",
            mode: .replyAll
        )
        #expect(reply.to.map(\.email) == replyAll.to.map(\.email))
        #expect(replyAll.cc.isEmpty)
    }

    @Test("Reply subject adds Re prefix once")
    func replySubjectPrefix() {
        #expect(ReplyRecipientResolver.replySubject(fromOriginalSubject: "Hello") == "Re: Hello")
        #expect(ReplyRecipientResolver.replySubject(fromOriginalSubject: "Re: Hello") == "Re: Hello")
    }
}

struct ReplyDraftMimeTests {

    @Test("MIME includes To, Cc, threading headers")
    func mimeContainsRecipientsAndThreading() {
        let service = GmailAPIService.shared
        let account = GmailAccount(
            id: "me@mycompany.com",
            email: "me@mycompany.com",
            name: "Me",
            accessToken: "token",
            refreshToken: nil,
            tokenExpiry: nil,
            lastSync: nil,
            unreadEmailsNextPageToken: nil
        )
        let headers = [
            GmailHeader(name: "From", value: "Alice <alice@example.com>"),
            GmailHeader(name: "To", value: "me@mycompany.com"),
            GmailHeader(name: "Subject", value: "Question"),
            GmailHeader(name: "Message-ID", value: "<msg-1@example.com>"),
            GmailHeader(name: "References", value: "<parent@example.com>")
        ]
        let payload = GmailPayload(
            mimeType: "text/plain",
            headers: headers,
            parts: nil,
            body: GmailBody(data: nil, size: nil)
        )
        let message = GmailMessage(
            id: "m1",
            threadId: "t1",
            snippet: "Hi",
            payload: payload,
            labelIds: ["INBOX"],
            internalDate: "0"
        )
        let envelope = ReplyDraftEnvelope(
            to: [ReplyMailboxAddress(email: "alice@example.com", displayName: "Alice")],
            cc: [ReplyMailboxAddress(email: "bob@example.com")],
            subject: "Re: Question",
            body: "Thanks!"
        )
        let raw = service.buildReplyRFC2822Message(
            account: account,
            original: message,
            envelope: envelope
        )
        #expect(raw.contains("To: \"Alice\" <alice@example.com>"))
        #expect(raw.contains("Cc: bob@example.com"))
        #expect(raw.contains("Subject: Re: Question"))
        #expect(raw.contains("In-Reply-To: <msg-1@example.com>"))
        #expect(raw.contains("References: <parent@example.com> <msg-1@example.com>"))
        #expect(raw.contains("Thanks!"))
    }
}
