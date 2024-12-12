import SwiftUI

struct ContentView: View {
    @State private var submittedExportRequest = false
    @State private var submittedName = ""

    var body: some View {
        VStack {
            ARWrapper(submittedExportRequest: $submittedExportRequest, submittedName: $submittedName)
                .ignoresSafeArea()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
