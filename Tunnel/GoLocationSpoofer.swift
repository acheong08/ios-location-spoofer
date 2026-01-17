//
//  GoLocationSpoofer.swift
//  location-spoofer-tunnel
//
//  Swift wrapper for Go location spoofing library
//

import Foundation
import Logging

class GoLocationSpoofer {
    private let logger: Logging.Logger
    private var proxyHandle: UInt?

    private let caCertKey = "LOCATIONSPOOFER_CA_Certificate"
    private let caKeyKey = "LOCATIONSPOOFER_CA_PrivateKey"

    init(logger: Logging.Logger) {
        self.logger = logger
        self.proxyHandle = nil
        golocationspoofer_init()
    }

    func hello() {
        logger.info("Calling Go Location Spoofer hello function")
        golocationspoofer_hello()
    }

    func version() -> String {
        let cString = golocationspoofer_version()
        guard let cString = cString else {
            logger.error("Failed to get version from Go library")
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

        logger.info("CA certificates stored in UserDefaults")
    }

    private func generateAndStoreCertificates() -> (cert: String, key: String)? {
        logger.info("Generating new CA certificate pair")

        let result = golocationspoofer_generateca()
        guard let certPtr = result.r0, let keyPtr = result.r1 else {
            logger.error("Failed to generate CA certificates from Go library")
            return nil
        }

        let cert = String(cString: certPtr)
        let key = String(cString: keyPtr)

        free(certPtr)
        free(keyPtr)

        storeCertificates(cert: cert, key: key)

        logger.info("New CA certificate pair generated and stored")
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
            logger.info("Using stored CA certificates")
            certificates = stored
        } else if let generated = generateAndStoreCertificates() {
            logger.info("Generated new CA certificates")
            certificates = generated
        } else {
            logger.error("Failed to obtain CA certificates")
            return false
        }

        logger.info("Starting Go location spoofing proxy with MITM capabilities on 127.0.0.1:8080")

        if let lat = lat, let lon = lon {
            logger.info("Location spoofing coordinates: \(lat), \(lon)")
        } else {
            logger.info("No coordinates provided, running in transparent mode")
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
            logger.info("Go location spoofing proxy started successfully with handle: \(handle)")
            return true
        } else {
            logger.error("Failed to start Go location spoofing proxy")
            return false
        }
    }

    func stopProxy() -> Bool {
        logger.info("Stopping Go location spoofing proxy")

        guard let handle = self.proxyHandle else {
            logger.warning("No proxy handle found, proxy may not be running")
            return true
        }

        let result = golocationspoofer_stopproxy(UInt(handle))
        self.proxyHandle = nil

        if result == 0 {
            logger.info("Go location spoofing proxy stopped successfully")
            return true
        } else {
            logger.error("Failed to stop Go location spoofing proxy, error code: \(result)")
            return false
        }
    }

    func isRunning() -> Bool {
        return proxyHandle != nil
    }

}