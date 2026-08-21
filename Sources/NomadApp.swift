import SwiftUI

@main
struct NomadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Text("Привет!")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                Button("Тест") {
                    print("Кнопка нажата")
                }
                .padding()
                .background(Color.cyan)
                .cornerRadius(10)
                .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
}
