//
//  ARWrapper.swift
//  C_ALL_With_Avoidance
//
//  Created by SSW - Design Team  on 12/11/24.
//

//
//  CompassView.swift
//  C_ALL_With_Path
//
//  Created by SSW - Design Team  on 11/28/24.
//

import SwiftUI
import CoreLocation

struct CompassView: View {
    @ObservedObject var compassViewModel: CompassViewModel

    var body: some View {
        ZStack {
            // Compass Circle
            Circle()
                .stroke(Color.gray, lineWidth: 2)
                .frame(width: 100, height: 100)

            // North Label
            Text("N")
                .font(.caption)
                .fontWeight(.bold)
                .offset(y: -45)

            // Compass Arrow
            ArrowShape()
                .fill(Color.red)
                .frame(width: 20, height: 60)
                .rotationEffect(Angle(degrees: -compassViewModel.currentHeading))
        }
        .padding()
    }
}

// Custom Arrow Shape
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arrowHeadHeight = rect.height * 0.7
        let arrowWidth = rect.width

        // Draw arrow
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)) // Top
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arrowHeadHeight)) // Right
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 4, y: rect.minY + arrowHeadHeight)) // Right Inner
        path.addLine(to: CGPoint(x: rect.midX + arrowWidth / 4, y: rect.maxY)) // Right Bottom
        path.addLine(to: CGPoint(x: rect.midX - arrowWidth / 4, y: rect.maxY)) // Left Bottom
        path.addLine(to: CGPoint(x: rect.midX - arrowWidth / 4, y: rect.minY + arrowHeadHeight)) // Left Inner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + arrowHeadHeight)) // Left
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
