//
//  ContentView.swift
//  CreatingLidarModel
//
//  Created by SSW - Design Team  on 11/14/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var submittedExportRequest = false
    @State private var exportedURL: URL?
    
    var body: some View{
        VStack{
            ARWrapper(submittedExportRequest: $submittedExportRequest, exportedURL: $exportedURL)
            Button(action: {
                //This will export the current model that is being displayed
                submittedExportRequest.toggle()
            }){
                Text("Export")
            }
        }
    }
    
}


struct ContentView_Previews: PreviewProvider{
    static var previews: some View{
        ContentView()
    }
}
    
    
    
    
    
    
    
    
    /*
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
*/
