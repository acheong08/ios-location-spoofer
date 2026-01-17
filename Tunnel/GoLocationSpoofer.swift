//
//  GoLocationSpoofer.swift
//  location-spoofer-tunnel
//
//  Swift wrapper for Go location spoofing library
//

import Foundation
import os.log

class GoLocationSpoofer {
    private var proxyHandle: UInt?

    private let caCertKey = "LOCATIONSPOOFER_CA_Certificate"
    private let caKeyKey = "LOCATIONSPOOFER_CA_PrivateKey"

    init() {
        self.proxyHandle = nil
        golocationspoofer_init()
    }

    func hello() {
        golocationspoofer_hello()
    }

    func version() -> String {
        let cString = golocationspoofer_version()
        guard let cString = cString else {
            return "unknown"
        }

        let version = String(cString: cString)
        free(cString)

        return version
    }

    private func getStoredCertificates() -> (cert: String, key: String)? {
        let userDefaults = UserDefaults.standard

        guard let cert = userDefaults.string(forKey: caCertKey),
            let key = userDefaults.string(forKey: caKeyKey)
        else {
            return nil
        }

        return (cert: cert, key: key)
    }

    private func storeCertificates(cert: String, key: String) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(cert, forKey: caCertKey)
        userDefaults.set(key, forKey: caKeyKey)
        userDefaults.synchronize()
    }

    private func generateAndStoreCertificates() -> (cert: String, key: String)? {
        let result = golocationspoofer_generateca()
        guard let certPtr = result.r0, let keyPtr = result.r1 else {
            return nil
        }

        let cert = String(cString: certPtr)
        let key = String(cString: keyPtr)

        free(certPtr)
        free(keyPtr)

        storeCertificates(cert: cert, key: key)

        return (cert: cert, key: key)
    }

    func getCACertificate() -> String? {
        if let stored = getStoredCertificates() {
            return stored.cert
        }

        if let generated = generateAndStoreCertificates() {
            return generated.cert
        }

        return nil
    }

    func startProxy(lat: Double?, lon: Double?) -> Bool {
        let certificates: (cert: String, key: String)

        if let stored = getStoredCertificates() {
            certificates = stored
        } else if let generated = generateAndStoreCertificates() {
            certificates = generated
        } else {
            return false
        }

        let handle = certificates.cert.withCString { certPtr in
            certificates.key.withCString { keyPtr in
                golocationspoofer_startproxy(
                    UnsafeMutablePointer<CChar>(mutating: certPtr),
                    UnsafeMutablePointer<CChar>(mutating: keyPtr),
                    lat ?? 0.0,
                    lon ?? 0.0,
                    (lat != nil && lon != nil) ? 1 : 0
                )
            }
        }

        if handle != 0 {
            self.proxyHandle = UInt(handle)
            os_log("Proxy handle: %u", log: OSLog.default, type: .info, handle)
            return true
        } else {
            return false
        }
    }

    func stopProxy() -> Bool {
        guard let handle = self.proxyHandle else {
            return true
        }

        let result = golocationspoofer_stopproxy(UInt(handle))
        self.proxyHandle = nil

        return result == 0
    }

    func isRunning() -> Bool {
        return proxyHandle != nil
    }

}