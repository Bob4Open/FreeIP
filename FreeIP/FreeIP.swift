//
//  FreeIP.swift
//  FreeIP
//
//  Created by Boni on 2021/7/28.
//

import Foundation
import SystemConfiguration

fileprivate let kIPRegular = "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
fileprivate let kIOSCellular = "pdp_ip0"
fileprivate let kIOSWifi = "en0"
fileprivate let kIOSVpn = "utun0"
fileprivate let kIPAddrIpv4 = "ipv4"
fileprivate let kIPAddrIpv6 = "ipv6"

public class FreeIP: NSObject {
    static let header = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9",
        "Accept-Encoding": "gzip, deflate, br",
        "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7",
        "Connection": "keep-alive",
    ]

    enum IPSource: String, CaseIterable {
        case testIpv6 = "https://ipv4.lookup.test-ipv6.com/ip/?asn=1&testdomain=test-ipv6.com"
        case zxinc = "https://v4.ip.zxinc.org/info.php?type=json"
        case ipip = "https://myip.ipip.net/"
        case ipchaxun = "https://2021.ipchaxun.com/"
        case ip138 = "https://2021.ip138.com/"

        static var random: IPSource {
            let randomIndex = Int(arc4random_uniform(UInt32(IPSource.allCases.count)))
            return [.testIpv6, .zxinc, .ipip, .ipchaxun, .ip138][randomIndex]
        }
    }

    fileprivate class func parseData(_ content: String, _ rawIp: inout String) throws {
        let regex = try NSRegularExpression(pattern: kIPRegular, options: NSRegularExpression.Options(arrayLiteral: .caseInsensitive, .anchorsMatchLines, .dotMatchesLineSeparators))

        let matches = regex.matches(in: content, options: NSRegularExpression.MatchingOptions.reportProgress, range: NSMakeRange(0, content.count))

        matches.forEach({ result in
            let startIndex = content.index(content.startIndex, offsetBy: result.range.location)
            let endIndex = content.index(content.startIndex, offsetBy: result.range.location + result.range.length)
            let range = startIndex ..< endIndex
            rawIp = String(content[range])
            return
        })
    }

    @objc public class func fetchPublicIP(_ timeout: TimeInterval, callback: @escaping ((String, Error?) -> Void)) {
        if let url = URL(string: IPSource.random.rawValue) {
            let config = URLSessionConfiguration.default
            config.httpAdditionalHeaders = header
            config.timeoutIntervalForRequest = timeout

            let session = URLSession(configuration: config)
            let task = session.dataTask(with: url) { data, response, error in
                var rawIp = "0.0.0.0"
                if let resp = response as? HTTPURLResponse {
                    if resp.statusCode == 200 {
                        if let content = String(data: data ?? Data(), encoding: .utf8) {
                            do {
                                try parseData(content, &rawIp)
                            } catch {
                                DispatchQueue.main.async {
                                    callback(rawIp, error)
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    callback(rawIp, error)
                }
            }
            task.resume()
        }
    }

    @objc public class func fetchLocalIP(_ preferIPv4: Bool = true) -> String {
        let status = Reachability.currentReachabilityStatus()
        guard status != .notReachable else {
            return "0.0.0.0"
        }
        
        let ipv4 = ["\(kIOSVpn)/\(kIPAddrIpv4)",
                    "\(kIOSVpn)/\(kIPAddrIpv6)",
                    "\(kIOSWifi)/\(kIPAddrIpv4)",
                    "\(kIOSWifi)/\(kIPAddrIpv6)",
                    "\(kIOSCellular)/\(kIPAddrIpv4)",
                    "\(kIOSCellular)/\(kIPAddrIpv6)"]

        let ipv6 = ["\(kIOSVpn)/\(kIPAddrIpv6)",
                    "\(kIOSVpn)/\(kIPAddrIpv4)",
                    "\(kIOSWifi)/\(kIPAddrIpv6)",
                    "\(kIOSWifi)/\(kIPAddrIpv4)",
                    "\(kIOSCellular)/\(kIPAddrIpv6)",
                    "\(kIOSCellular)/\(kIPAddrIpv4)"]

        let searchArray = preferIPv4 ? ipv4 : ipv6
        let addresses = getIPAddresses()
        let networkType = status == .viaWiFi ? kIOSWifi : kIOSCellular
        for key in searchArray {
            if key == "\(networkType)/\(kIPAddrIpv4)", let ip = addresses[key] {
                return ip
            }
        }
        return "0.0.0.0"
    }

    @objc class func getIPAddresses() -> [String: String] {
        var addresses = [String: String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let flags = Int32(ptr!.pointee.ifa_flags)
                var addr = ptr!.pointee.ifa_addr.pointee
                let name = String(cString: ptr!.pointee.ifa_name)
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                    if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                        let type = addr.sa_family == UInt8(AF_INET) ? kIPAddrIpv4 : kIPAddrIpv6
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                            if let address = String(validatingUTF8: hostname) {
                                addresses["\(name)/\(type)"] = address
                            }
                        }
                    }
                }
                ptr = ptr!.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return addresses
    }
}
