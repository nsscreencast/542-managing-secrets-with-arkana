//
//  UnsplashApiClient.swift
//  UnsplashBrowser
//
//  Created by Ben Scheirman on 1/24/22.
//

import Foundation
import SwiftUI
import ArkanaKeys
import ArkanaKeysInterfaces

extension ArkanaKeys {
    static var currentEnvironment: ArkanaKeysEnvironmentProtocol {
        #if DEBUG
        ArkanaKeys.Staging()
        #else
        ArkanaKeys.Production()
        #endif
    }
}

class EnvProvider<T>: ObservableObject {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

struct UnsplashAPIClientEnvironmentKey: EnvironmentKey {
    static var defaultValue = EnvProvider<UnsplashApiClient>(.init())
}

extension EnvironmentValues {
    var unsplashClient: UnsplashApiClient {
        get { self[UnsplashAPIClientEnvironmentKey.self].value }
        set { self[UnsplashAPIClientEnvironmentKey.self] = .init(newValue) }
    }
}

class UnsplashApiClient {
    enum Errors: Error {
        case invalidResponse
        case requestError
    }
    
    private let accessKey: String
    private let secretKey: String
    
    init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
    
    convenience init() {
        let analyticsKey = ArkanaKeys.currentEnvironment.analyticsKey

        let accessKey = ArkanaKeys.Global().unsplashAccessKey
        let secretKey = ArkanaKeys.Global().unsplashSecretKey
        self.init(accessKey: accessKey, secretKey: secretKey)
    }
    
    func photos(page: Int = 1) async throws -> PaginagedResponse<UnsplashPhoto> {
        print("Fetching page \(page)")
        let url = URL(string: "https://api.unsplash.com/photos?page=\(page)")!
        var request = URLRequest(url: url)
        request.addValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse else { throw Errors.invalidResponse }
        guard http.statusCode == 200 else { throw Errors.requestError }
        
        let decoder = JSONDecoder()
        let photos = try decoder.decode([UnsplashPhoto].self, from: data)
        print("Page \(page) has \(photos.count) results")
        
        let lastPage: Int
        if let metaLinks = http.value(forHTTPHeaderField: "Link")?.split(separator: ","),
           let lastLink = metaLinks.first(where: { $0.contains("rel=\"last\"")}),
           let pageParameter = extractPageNumber(from: String(lastLink))
        {
            lastPage = pageParameter
        } else {
            lastPage = page
        }
        
        return PaginagedResponse(page: page, totalPages: lastPage, results: photos)
    }
    
    private func extractPageNumber(from urlString: String) -> Int? {
        let regex = try! NSRegularExpression(pattern: "page=(?<page>\\d+)", options: [])
        guard let match = regex.firstMatch(in: urlString, options: [], range: NSMakeRange(0, urlString.count)) else {
            return nil
        }
        let pageRange = match.range(withName: "page")
        guard pageRange.location != NSNotFound else { return nil }
        return Int(String(urlString[Range(pageRange, in: urlString)!]))
    }
}

struct PaginagedResponse<T: Codable> {
    let page: Int
    let totalPages: Int
    let results: [T]
}

extension PaginagedResponse: Sendable where T: Sendable {}

struct UnsplashPhoto: Codable, Identifiable {
    let id: String
    let width: Int
    let height: Int
    let description: String?
    let urls: ImageURLs
}

struct ImageURLs: Codable {
    private var urls: [UnsplashImageSize: URL]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        urls = [:]
        for key in container.allKeys {
            guard let size = UnsplashImageSize(rawValue: key.stringValue) else {
                print("Warning, skipping size: \(key.stringValue)")
                continue
            }
            urls[size] = try container.decode(URL.self, forKey: key)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in urls {
            try container.encode(value, forKey: .init(stringValue: key.rawValue))
        }
    }
    
    subscript(_ size: UnsplashImageSize) -> URL? {
        urls[size]
    }
    
    struct DynamicKey: CodingKey {
        init(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = String(intValue)
        }
        
        var stringValue: String
        var intValue: Int?
    }
}

enum UnsplashImageSize: String, Codable {
    case raw = "raw"
    case full = "full"
    case regular = "regular"
    case small = "small"
    case thumb = "thumb"
}
