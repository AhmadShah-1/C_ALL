import SwiftUI

struct CompassView: View {
    @Binding var angle: Float
    @Binding var obstacleAvoidance: Bool
    
    @State private var prevAngle: Float = 0
    @State private var prevObstacleState: Bool = false
    @State private var pulseSize: CGFloat = 1.0
    @State private var arrowOpacity: Double = 1.0
    
    private func getDirectionColor() -> Color {
        // Geo direction is always white
        return .white
    }
    
    var body: some View {
        ZStack {
            // Compass background
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: 2)
                .frame(width: 100, height: 100)
                .background(Circle().fill(Color.black.opacity(0.3)))
            
            // Cardinal directions (static to avoid recreation)
            Group {
                Text("N").foregroundColor(.white).position(x: 50, y: 15)
                Text("E").foregroundColor(.white).position(x: 85, y: 50)
                Text("S").foregroundColor(.white).position(x: 50, y: 85)
                Text("W").foregroundColor(.white).position(x: 15, y: 50)
            }
            
            // Rotating pointer
            Group {
                // Main arrow
                Image(systemName: "location.north.fill")
                    .resizable()
                    .frame(width: 20, height: 25)
                    .foregroundColor(getDirectionColor())
                    .rotationEffect(Angle(radians: Double(angle)))
                    .scaleEffect(pulseSize)
                    .opacity(arrowOpacity)
                
                // Label to indicate this is the geo-navigation compass
                Text("TARGET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .position(x: 50, y: 40)
            }
        }
        .frame(width: 100, height: 100)
        .onChange(of: angle) { newValue in
            // Only log significant changes to avoid console spam
            if abs(newValue - prevAngle) > 0.1 {
                print("DEBUG: Geo compass angle updated to \(newValue)")
                prevAngle = newValue
            }
        }
    }
}

// NEW: SafePathCompassView for obstacle avoidance direction
struct SafePathCompassView: View {
    @Binding var angle: Float
    @Binding var isActive: Bool
    
    @State private var prevAngle: Float = 0
    @State private var pulseSize: CGFloat = 1.0
    @State private var arrowOpacity: Double = 1.0
    
    private func getDirectionColor() -> Color {
        // Blue color scheme for safe path
        return .blue
    }
    
    var body: some View {
        ZStack {
            // Compass background - blue theme
            Circle()
                .stroke(Color.blue.opacity(0.7), lineWidth: 2)
                .frame(width: 100, height: 100)
                .background(Circle().fill(Color.black.opacity(0.3)))
            
            // Different indicator for safe path
            Group {
                // Path visualization with blue to red gradient
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .purple, .red, .orange, .yellow, .green, .blue]),
                            center: .center
                        )
                    )
                    .frame(width: 80, height: 80)
                    .opacity(0.3)
                
                // Main arrow showing safe direction
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.blue)
                    .rotationEffect(Angle(radians: Double(angle)))
                    .scaleEffect(pulseSize)
                    .opacity(isActive ? 1.0 : 0.4)
                
                // Label to indicate this is for safety/obstacle avoidance
                Text("SAFE PATH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .position(x: 50, y: 75)
                    .opacity(isActive ? 1.0 : 0.6)
            }
        }
        .frame(width: 100, height: 100)
        .onChange(of: isActive) { newValue in
            // Animation when active state changes
            if newValue {
                withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseSize = 1.15
                    arrowOpacity = 0.8
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulseSize = 1.0
                    arrowOpacity = 0.5
                }
            }
        }
        .onChange(of: angle) { newValue in
            // Only log significant changes
            if abs(newValue - prevAngle) > 0.1 && isActive {
                print("DEBUG: Safe path compass updated to \(newValue)")
                prevAngle = newValue
            }
        }
    }
}

struct CompassView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 40) {
                HStack(spacing: 40) {
                    CompassView(angle: .constant(.pi / 4), obstacleAvoidance: .constant(false))
                    
                    SafePathCompassView(angle: .constant(-.pi / 3), isActive: .constant(true))
                }
                
                HStack(spacing: 40) {
                    CompassView(angle: .constant(-.pi / 4), obstacleAvoidance: .constant(true))
                    
                    SafePathCompassView(angle: .constant(.pi / 6), isActive: .constant(false))
                }
            }
        }
    }
}
