import SwiftUI

/// The privacy policy or support. The app ships their text (`legal.json`, written from
/// the website's by `npm run legal:export` in frontend/), so they open without a network.
enum SitePage: String, Identifiable {
    case privacy, support

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .privacy: "Privacy policy"
        case .support: "Support"
        }
    }

    /// The same page on ironsage.app, in the app's language.
    var url: URL { Site.page(rawValue) }
}

/// The text of both pages in English and Chinese, as the website has it.
struct LegalText: Decodable {
    struct Page: Decodable {
        let title: String
        let updated: String
        let intro: String
        let sections: [Section]
    }

    struct Section: Decodable {
        let heading: String
        let paragraphs: [String]?
        let items: [String]?
    }

    let contactEmail: String
    let privacy: [String: Page]
    let support: [String: Page]

    static let shipped: LegalText = {
        guard let url = Bundle.main.url(forResource: "legal", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let text = try? JSONDecoder().decode(LegalText.self, from: data)
        else { preconditionFailure("legal.json is missing from the app") }
        return text
    }()

    func page(_ page: SitePage, chinese: Bool) -> Page? {
        (page == .privacy ? privacy : support)[chinese ? "zh" : "en"]
    }
}

/// Opens a page in a sheet, as a link would.
struct SitePageButton: View {
    let page: SitePage
    @State private var isShowing = false

    var body: some View {
        Button(page.title) { isShowing = true }
            .sheet(isPresented: $isShowing) {
                SitePageSheet(page: page)
            }
    }
}

/// The page in a sheet four fifths of the screen high, pulled up to full height.
struct SitePageSheet: View {
    let page: SitePage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let legal = LegalText.shipped
        NavigationStack {
            ScrollView {
                if let text = legal.page(page, chinese: AppLanguage.isChinese) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !text.updated.isEmpty {
                            Text(verbatim: text.updated)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)
                        }
                        Text(linked(text.intro, email: legal.contactEmail))
                        ForEach(Array(text.sections.enumerated()), id: \.offset) { _, section in
                            Text(verbatim: section.heading)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 28)
                            ForEach(Array((section.paragraphs ?? []).enumerated()), id: \.offset) { _, paragraph in
                                Text(linked(paragraph, email: legal.contactEmail))
                                    .padding(.top, 8)
                            }
                            ForEach(Array((section.items ?? []).enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(verbatim: "•")
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                    Text(linked(item, email: legal.contactEmail))
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .background(Color.appBackground)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Open in Safari", systemImage: "safari") {
                        openURL(page.url)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    /// The support address as a link that opens a new email.
    private func linked(_ text: String, email: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: email) {
            attributed[range].link = URL(string: "mailto:\(email)")
        }
        return attributed
    }
}
