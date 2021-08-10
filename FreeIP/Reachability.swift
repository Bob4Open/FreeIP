//
//  Reachability.swift
//  FreeIP
//
//  Created by Boni on 2021/7/29.
//

import SystemConfiguration

enum NetworkStatus: Int {
    case notReachable = 0
    case viaWiFi
    case viaWWAN
}

class Reachability {
    class func currentReachabilityStatus() -> NetworkStatus {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }

        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return .notReachable
        }
        
        return networkStatusForFlags(flags)
    }
    
    class func networkStatusForFlags(_ flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        if (flags.rawValue & SCNetworkReachabilityFlags.reachable.rawValue) == 0 {
            return .notReachable
        }

        var returnValue: NetworkStatus = .notReachable

        if ((flags.rawValue & SCNetworkReachabilityFlags.connectionRequired.rawValue) == 0) {
            returnValue = .viaWiFi;
        }

        if ((((flags.rawValue & SCNetworkReachabilityFlags.connectionOnDemand.rawValue ) != 0) ||
                (flags.rawValue & SCNetworkReachabilityFlags.connectionOnTraffic.rawValue) != 0)) {
            if ((flags.rawValue & SCNetworkReachabilityFlags.interventionRequired.rawValue) == 0) {
                returnValue = .viaWiFi;
            }
        }

        if ((flags.rawValue & SCNetworkReachabilityFlags.isWWAN.rawValue) == SCNetworkReachabilityFlags.isWWAN.rawValue) {
            returnValue = .viaWWAN;
        }
        
        return returnValue;
    }
}
