import Testing
@testable import EmptyMyInboxShared

@MainActor
struct ReplyDraftViewModelTests {

  private func sampleEmail() -> EmailDetail {
    EmailDetail(
      id: 1,
      gmail_id: "g1",
      thread_id: "t1",
      subject: "Project update",
      sender: "alice@example.com",
      sender_name: "Alice",
      recipients_to: "me@mycompany.com",
      recipients_cc: "bob@example.com",
      recipients_bcc: nil,
      body_text: "Can we meet tomorrow?",
      body_html: nil,
      snippet: "Can we meet tomorrow?",
      is_read: false,
      is_starred: false,
      labels: ["INBOX", "UNREAD"],
      received_at: "2026-05-19T12:00:00Z",
      account_email: "me@mycompany.com",
      created_at: "2026-05-19T12:00:00Z"
    )
  }

  @Test("Initial mode applies recipient fields from cached detail")
  func appliesRecipientsOnModeChange() {
    let email = sampleEmail()
    let vm = ReplyDraftViewModel(intent: ReplyIntent(email: email, mode: .reply))
    vm.applyRecipientsForCurrentMode()
    #expect(!vm.toField.isEmpty)
    #expect(vm.subject.hasPrefix("Re:"))

    vm.mode = .replyAll
    #expect(vm.showCcBcc == true)
  }

  @Test("Current envelope reflects edited fields")
  func currentEnvelopeFromFields() {
    let email = sampleEmail()
    let vm = ReplyDraftViewModel(intent: ReplyIntent(email: email, mode: .reply))
    vm.toField = "alice@example.com"
    vm.subject = "Re: Project update"
    vm.bodyText = "Sounds good."
    let envelope = vm.currentEnvelope()
    #expect(envelope.to.count == 1)
    #expect(envelope.to[0].email == "alice@example.com")
    #expect(envelope.body == "Sounds good.")
  }

  @Test("Insert quick reply appends to existing body")
  func insertQuickReplyAppends() {
    let email = sampleEmail()
    let vm = ReplyDraftViewModel(intent: ReplyIntent(email: email, mode: .reply))
    vm.bodyText = "Hi there,"
    vm.quickReplyDraft = "I'll follow up tomorrow."
    vm.insertQuickReply()
    #expect(vm.bodyText.contains("Hi there,"))
    #expect(vm.bodyText.contains("I'll follow up tomorrow."))
  }
}
