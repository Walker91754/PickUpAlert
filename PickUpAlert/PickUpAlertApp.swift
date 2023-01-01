//
//  PickUpAlertApp.swift
//  PickUpAlert
//
//  Created by TZUCHE HUANG on 2023/1/1.
//

import SwiftUI
//import AppTrackingTransparency
import GoogleMobileAds

@main
struct PickUpAlertApp: App {
    
    
    //Use init() in place of ApplicationDidFinishLaunchWithOptions in App Delegate
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        /*
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            //User has not indicated their choice for app tracking
            //You may want to show a pop-up explaining why you are collecting their data
            //Toggle any variables to do this here
        } else {
            ATTrackingManager.requestTrackingAuthorization { status in
                //Whether or not user has opted in initialize GADMobileAds here it will handle the rest
                                                            
                GADMobileAds.sharedInstance().start(completionHandler: nil)
            }
        } */
    }

    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                SwiftUIBannerAd(adPosition: .bottom, adUnitId: SwiftUIMobileAds.bannerId)
            }
        }
    }
}

