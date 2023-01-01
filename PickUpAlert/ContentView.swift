//
//  ContentView.swift
//  PickUpAlert
//
//  Created by TZUCHE HUANG on 2023/1/1.
//

import SwiftUI
import AVFoundation
import Photos
import Vision


struct ContentView: View {
    
    @State private var showSettingsView: Bool = false //new sheet
    
    var body: some View {
            if showSettingsView {
                SettingsView(showSettingsView: self.$showSettingsView)
            } else {
                CameraView(showSettingsView: self.$showSettingsView)
            }
        
    }
    
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone SE (2nd generation)")
    }

}




struct CameraView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @Binding var showSettingsView: Bool
    
    @StateObject var camera = CameraModel()
    var body: some View {
        ZStack{
            CameraPreview(camera: camera)
            //Color.black
                .ignoresSafeArea(.all, edges: .all)
            
            VStack{
                    HStack {
                        
                        Button(action: {showSettingsView.toggle()
                            camera.isEnabledScan.toggle()
                        }, label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(Color.gray)
                                .padding()
                                //.background(Color.white)
                                //.clipShape(Circle())
                        })
                        .padding(.leading, 10)
                        Spacer()
                    }
                
                Spacer()
                
                HStack{
                    
                    Button(action: {camera.startResumeSession() }, label: {
                        Image(systemName: "scope")
                            .foregroundColor(camera.scanButtonColor)
                            .padding()
                            //.background(Color.white)
                            .clipShape(Circle())
                            
                    })
                    //.disabled(!camera.isEnabledScan)
                    .padding(.bottom, 50)
                    
                    Button(action: {camera.movieRecording() }, label: {
                        Image(systemName: camera.recordButtonImage)
                            .foregroundColor(camera.recordButtonColor)
                            .padding()
                            .clipShape(Circle())
                    })
                    .disabled(!camera.isRecordEnabled)
                    .padding(.bottom, 50)
                    
                    Button(action: {camera.isSpeakTarget.toggle() }, label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(camera.isSpeakTarget ? Color.blue : Color.gray)
                            .padding()
                            .clipShape(Circle())
                    })
                    .disabled(!camera.isRecordEnabled)
                    .padding(.bottom, 50)
                    
                    Button(action: {camera.isCapturedEnabled.toggle() }, label: {
                        Image(systemName: "video.bubble.left")
                            .foregroundColor(camera.isCapturedEnabled ? Color.cyan : Color.gray)
                            .padding()
                            .clipShape(Circle())
                    })
                    .disabled(!camera.isRecordEnabled)
                    .padding(.bottom, 50)
                }

            }
        }
        .onAppear(perform: {
            //GADMobileAds.sharedInstance().start(completionHandler: nil)
            camera.check()
            
            camera.setupLayers()
            camera.updateLayerGeometry()
            camera.sessionStartRunning()
        })
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("CameraView Active")
                //showSettingsView = true
            } else if newPhase == .inactive {
                print("CameraView Inactive")
            } else if newPhase == .background {
                print("CameraView Background")
                //camera.isEnabledScan = false
            }
        }
    }
}





// setting view for preview
struct CameraPreview: UIViewRepresentable {
    
    @ObservedObject var camera : CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        camera.rootLayer = camera.preview

        
        camera.preview.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        view.layer.addSublayer(camera.preview)
        
        return view
        
        
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        //camera.preview.connection?.videoOrientation = .portrait
    }
}

