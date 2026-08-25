import SwiftUI

struct LoadingView: View {
    let coordinator: AppStartupCoordinator
    let retry: () -> Void

    var body: some View {
        ZStack {
            Image("LoadingScreen")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage = coordinator.errorMessage {
                        Text(errorMessage)
                            .font(.headline)
                        Button("Probeer opnieuw", action: retry)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text(coordinator.statusText)
                            .font(.headline)
                        ProgressView(value: coordinator.progress)
                            .tint(.white)
                            .animation(.easeInOut(duration: 0.25), value: coordinator.progress)
                            .accessibilityLabel("Voortgang app laden")
                            .accessibilityValue("\(Int(coordinator.progress * 100)) procent")
                    }
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
