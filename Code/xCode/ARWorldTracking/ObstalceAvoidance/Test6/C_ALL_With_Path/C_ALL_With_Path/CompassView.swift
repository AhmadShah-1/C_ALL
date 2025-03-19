import SwiftUI
import CoreLocation

struct CompassView: View {
    @ObservedObject var compassViewModel: CompassViewModel

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray, lineWidth: 2)
                .frame(width: 100, height: 100)

            Text("N")
                .font(.caption)
                .fontWeight(.bold)
                .offset(y: -45)

            ArrowShape()
                .fill(Color.red)
                .frame(width: 20, height: 60)
                .rotationEffect(Angle(degrees: -compassViewModel.currentHeading))
        }
        .padding()
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arrowHeadHeight = rect.height * 0.7
        let arrowWidth = rect.width

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arrowHeadHeight))
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 4, y: rect.minY + arrowHeadHeight))
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 4, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - arrowWidth / 4, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - arrowWidth / 4, y: rect.minY + arrowHeadHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + arrowHeadHeight))
        path.closeSubpath()
        return path
    }
}

class CompassViewModel: NSObject, ObservableObject {
    @Published var currentHeading: Double = 0.0
    func updateHeading(_ heading: Double) {
        DispatchQueue.main.async {
            self.currentHeading = heading
        }
    }
}
