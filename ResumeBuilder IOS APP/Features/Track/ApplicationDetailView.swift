import SwiftUI

struct ApplicationDetailView: View {
    let application: ApplicationItem

    var body: some View {
        List {
            LabeledContent("Role", value: application.jobTitle ?? "-")
            LabeledContent("Company", value: application.companyName ?? "-")
            LabeledContent("Applied", value: application.appliedDate ?? "-")
            LabeledContent("Status", value: application.status ?? "applied")
        }
        .navigationTitle("Application")
    }
}
