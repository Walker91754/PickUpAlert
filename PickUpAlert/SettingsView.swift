//
//  SettingsView.swift
//  PickUpAlert
//
//  Created by TZUCHE HUANG on 2023/1/4.
//

import SwiftUI

struct SettingsView: View {
    @Binding var showSettingsView: Bool
    
    let defaultURL = URL(string:"https://www.google.com")!
    let privacyURL = URL(string:"https://sites.google.com/view/privacy-policy-for-pick-up-ale/")!
    let webURL = URL(string:"https://github.com/Walker91754")!
    
    var body: some View {
        NavigationView {
            List {
                //seetingsSection
                pickUpAlertSection
                applicationSection
            }
            .listStyle(GroupedListStyle())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {showSettingsView.toggle()}, label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(Color.gray)
                            //.padding()
                    })
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(showSettingsView: .constant(false))
            .previewDevice("iPhone SE (2nd generation)")
    }
}

extension SettingsView {
    private var pickUpAlertSection: some View {
        Section(header: Text("Pick Up Alert")) {
            VStack(alignment: .leading) {
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text("This app was developed to dectect objects with ML model  \"yolov5\". Turn capture mode on to record 5 seconds video. Enjoy it! 😁")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(Color.black)
                Spacer()
                HStack{
                    Image(systemName: "scope")
                        .foregroundColor(Color.yellow)
                        .clipShape(Circle())
                    Text("Scan: Doing objects detection in real-time with fast inference.")
                        .font(.callout)
                        .fontWeight(.light)
                        .foregroundColor(Color.black)
                }
                Spacer()
                HStack{
                    Image(systemName: "circle.fill")
                        .foregroundColor(Color.red)
                        .clipShape(Circle())
                    Text("Record: Perform the video recording.")
                        .font(.callout)
                        .fontWeight(.light)
                        .foregroundColor(Color.black)
                }
                Spacer()
                HStack{
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(Color.blue)
                        .clipShape(Circle())
                    Text("Voice: Speak the detections as voice notification.")
                        .font(.callout)
                        .fontWeight(.light)
                        .foregroundColor(Color.black)
                }
                Spacer()
                HStack{
                    Image(systemName: "video.bubble.left")
                        .foregroundColor(Color.cyan)
                        .clipShape(Circle())
                    Text("Capture: Automatically record the video while detecting target objects -- Huamn Face\", \"motorcycle\", \"bird\", \"cat\", \"dog\", \"bear\", \"horse\", \"cow\", \"sheep\"")
                        .font(.callout)
                        .fontWeight(.light)
                        .foregroundColor(Color.black)
                }
            }
        }
    }
    
    private var applicationSection: some View {
        Section(header: Text("Application")) {
            //Link("Terms and Service", destination: defaultURL)
            Link("Privacy Policy", destination: privacyURL)
            Link("Website", destination: webURL)
            //Link("Learn More", destination: defaultURL)
            
        }
    }
    
    private var seetingsSection: some View {
        Section() {

            
        }
    }
}
