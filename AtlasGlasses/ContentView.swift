import SwiftUI

enum AppTab: String, CaseIterable {
    case atlas = "Atlas"
    case talk = "Talk"
}

struct ContentView: View {
    @StateObject private var senses = SensesClient.shared
    @StateObject private var recorder = AudioRecorder()
    @State private var selectedTab: AppTab = .atlas

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .atlas:
                    AtlasWebView(url: URL(string: "https://nikitarogers.up.railway.app")!)
                        .ignoresSafeArea(edges: .bottom)
                case .talk:
                    PushToTalkView(recorder: recorder, senses: senses)
                }
            }

            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab == .atlas ? "globe" : "mic.fill")
                                .font(.system(size: 20))
                            Text(tab.rawValue)
                                .font(.caption2)
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .gray)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(.black.opacity(0.95))
        }
        .preferredColorScheme(.dark)
        .onAppear {
            senses.connect()
        }
    }
}

#Preview {
    ContentView()
}
