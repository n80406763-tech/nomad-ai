import SwiftUI

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        ZStack {
            // Темный фон (в стиле логотипа)
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            VStack {
                Text("Nomad AI")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.cyan)
                    .padding(.top, 40)
                
                Text("Офлайн Навигатор & Ассистент")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Spacer()
                
                // Статус GPS
                if locationManager.authorizationStatus == .notDetermined {
                    Button(action: {
                        locationManager.requestPermission()
                    }) {
                        Text("Включить GPS")
                            .font(.headline)
                            .foregroundColor(.black)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.cyan)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "location.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(locationManager.location != nil ? .cyan : .gray)
                        
                        if let loc = locationManager.location {
                            Text("Спутники найдены")
                                .font(.headline)
                                .foregroundColor(.green)
                            Text("Скорость: \(max(0, loc.speed) * 3.6, specifier: "%.0f") км/ч")
                                .font(.title2)
                        } else {
                            Text("Поиск сигнала GPS...")
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Spacer()
                
                // Кнопка микрофона (задел на ИИ)
                Button(action: {
                    print("ИИ Ассистент вызван")
                }) {
                    Image(systemName: "mic.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(20)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.cyan)
                        .clipShape(Circle())
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse {
                locationManager.startTracking()
            }
        }
    }
}
