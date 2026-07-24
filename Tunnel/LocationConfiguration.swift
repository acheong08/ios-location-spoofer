//
//  LocationConfiguration.swift
//  location-spoofer-tunnel
//
//  Shared configuration for location spoofing functionality
//

import Foundation

struct Coordinates {
    let latitude: Double
    let longitude: Double
}

class LocationConfiguration {
    static let shared = LocationConfiguration()

    private let userDefaults: UserDefaults
    private let suiteName = "group.dev.duti.location-spoofer"

    private enum Keys {
        static let latitude = "spoofed_latitude"
        static let longitude = "spoofed_longitude"
    }

    private init() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create UserDefaults with suite name: \(suiteName)")
        }
        self.userDefaults = defaults
        userDefaults.synchronize()
    }

    var currentCoordinates: Coordinates? {
        let lat = userDefaults.double(forKey: Keys.latitude)
        let lon = userDefaults.double(forKey: Keys.longitude)
        
        guard userDefaults.object(forKey: Keys.latitude) != nil,
              userDefaults.object(forKey: Keys.longitude) != nil else {
            return nil
        }
        
        return Coordinates(latitude: lat, longitude: lon)
    }

    func setCoordinates(latitude: Double, longitude: Double) {
        userDefaults.set(latitude, forKey: Keys.latitude)
        userDefaults.set(longitude, forKey: Keys.longitude)
        userDefaults.synchronize()
    }

    func clearCoordinates() {
        userDefaults.removeObject(forKey: Keys.latitude)
        userDefaults.removeObject(forKey: Keys.longitude)
        userDefaults.synchronize()
    }

    func synchronize() {
        userDefaults.synchronize()
    }
}