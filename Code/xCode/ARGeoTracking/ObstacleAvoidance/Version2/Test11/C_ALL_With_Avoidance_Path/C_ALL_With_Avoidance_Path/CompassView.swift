import SwiftUI

struct CompassView: View {
    /// The rotation angle (in degrees). (0° means the arrow points upward.)
    let angle: Double
    
    var body: some View {
        Image(systemName: "arrow.up")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 50, height: 50)
            .rotationEffect(.degrees(angle))
            .padding(10)
            .background(Color.white.opacity(0.8))
            .clipShape(Circle())
            .shadow(radius: 5)
    }
}

struct AvoidanceCompassView: View {
    /// The rotation angle (in degrees). (0° means the arrow points upward.)
    let angle: Double
    /// Whether there's a clear path in this direction
    let isPathClear: Bool
    
    // Determine color based on angle and clear path status
    private var compassColor: Color {
        if !isPathClear {
            return .red
        }
        
        // If pointing straight ahead
        if abs(angle) < 10 {
            return .green
        }
        
        // If suggesting a turn (left or right)
        return .yellow
    }
    
    var body: some View {
        Image(systemName: "arrow.up")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 50, height: 50)
            .rotationEffect(.degrees(angle))
            .padding(10)
            .background(compassColor.opacity(0.8))
            .clipShape(Circle())
            .shadow(radius: 5)
    }
}

struct CompassView_Previews: PreviewProvider {
    static var previews: some View {
        CompassView(angle: 45)
    }
}
