import SwiftUI

/// Searchable list of all `TimeZone` identifiers for choosing a secondary column (Day / Week schedule).
struct CalendarTimeZonePickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let ids = TimeZone.knownTimeZoneIdentifiers.sorted()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return ids }
        return ids.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { id in
                Button {
                    selection = id
                    dismiss()
                } label: {
                    HStack {
                        Text(id.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        if id == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("Second time zone")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $query, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
