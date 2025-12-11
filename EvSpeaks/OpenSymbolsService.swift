//
//  OpenSymbolsService.swift
//  Ev Speaks
//
//  Service for OpenSymbols API integration
//

import Foundation
import UIKit

struct SymbolResult: Identifiable, Codable {
    let id: String
    let image_url: String
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case image_url
        case imageUrl
        case image
        case name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle id as String or Int
        if let idString = try? container.decode(String.self, forKey: .id) {
            id = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "id must be String or Int")
        }
        
        // Try different image URL field names
        if let url = try? container.decode(String.self, forKey: .image_url) {
            image_url = url
        } else if let url = try? container.decode(String.self, forKey: .imageUrl) {
            image_url = url
        } else if let url = try? container.decode(String.self, forKey: .image) {
            image_url = url
        } else {
            throw DecodingError.dataCorruptedError(forKey: .image_url, in: container, debugDescription: "image_url not found")
        }
        
        name = try? container.decode(String.self, forKey: .name)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(image_url, forKey: .image_url)
        try container.encodeIfPresent(name, forKey: .name)
    }
    
    init(id: String, image_url: String, name: String?) {
        self.id = id
        self.image_url = image_url
        self.name = name
    }
}

struct TokenResponse: Codable {
    let access_token: String
}

struct SymbolsResponse: Codable {
    let symbols: [SymbolResult]?
    
    enum CodingKeys: String, CodingKey {
        case symbols
    }
}

class OpenSymbolsService: ObservableObject {
    @Published var isSearching = false
    @Published var searchResults: [SymbolResult] = []
    @Published var errorMessage: String?
    
    private let baseURL = "https://www.opensymbols.org"
    private let secret = "9db8310ec72140c4b335437e"
    private var accessToken: String?
    
    // Get access token
    func getAccessToken() async throws -> String {
        // Return cached token if available
        if let token = accessToken {
            return token
        }
        
        guard let url = URL(string: "\(baseURL)/api/v2/token") else {
            throw NSError(domain: "OpenSymbolsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Encode secret as form data
        let bodyString = "secret=\(secret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenSymbolsService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get access token"])
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.access_token
        return tokenResponse.access_token
    }
    
    // Search symbols
    func searchSymbols(query: String) async throws -> [SymbolResult] {
        await MainActor.run {
            isSearching = true
            errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                isSearching = false
            }
        }
        
        // Get access token first
        let token = try await getAccessToken()
        
        // Build search URL with access_token as query parameter
        var components = URLComponents(string: "\(baseURL)/api/v2/symbols")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "locale", value: "en"),
            URLQueryItem(name: "safe", value: "0"),
            URLQueryItem(name: "access_token", value: token)
        ]
        
        guard let url = components.url else {
            throw NSError(domain: "OpenSymbolsService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid search URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenSymbolsService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("OpenSymbols API Error (Status \(httpResponse.statusCode)): \(errorMessage)")
            throw NSError(domain: "OpenSymbolsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(errorMessage)"])
        }
        
        // Log the raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("OpenSymbols API Response: \(responseString.prefix(500))")
        }
        
        // Try to parse as JSON first to see the structure
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            let errorMsg = "Response is not valid JSON"
            print("Parse Error: \(errorMsg)")
            await MainActor.run {
                self.errorMessage = errorMsg
            }
            throw NSError(domain: "OpenSymbolsService", code: -5, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        print("JSON Object Type: \(type(of: jsonObject))")
        
        // Parse response - try different formats
        do {
            // Try parsing as array first (most common format)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase // Handle snake_case to camelCase
            let results = try decoder.decode([SymbolResult].self, from: data)
            
            await MainActor.run {
                self.searchResults = results
            }
            
            return results
        } catch let arrayError {
            print("Array parse error: \(arrayError)")
            
            // Try parsing as wrapped object
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let symbolsResponse = try decoder.decode(SymbolsResponse.self, from: data)
                let results = symbolsResponse.symbols ?? []
                
                await MainActor.run {
                    self.searchResults = results
                }
                
                return results
            } catch let objectError {
                print("Object parse error: \(objectError)")
                
                // Try manual parsing if it's a dictionary
                if let dict = jsonObject as? [String: Any] {
                    // Check if it's a dictionary with a results/symbols key
                    var symbolsArray: [[String: Any]]?
                    if let symbols = dict["symbols"] as? [[String: Any]] {
                        symbolsArray = symbols
                    } else if let results = dict["results"] as? [[String: Any]] {
                        symbolsArray = results
                    }
                    
                    if let symbolsArray = symbolsArray {
                        var results: [SymbolResult] = []
                        for symbolDict in symbolsArray {
                            var idString: String?
                            var imageUrl: String?
                            
                            // Get id
                            if let id = symbolDict["id"] as? String {
                                idString = id
                            } else if let id = symbolDict["id"] as? Int {
                                idString = String(id)
                            }
                            
                            // Get image URL
                            if let url = symbolDict["image_url"] as? String {
                                imageUrl = url
                            } else if let url = symbolDict["imageUrl"] as? String {
                                imageUrl = url
                            } else if let url = symbolDict["image"] as? String {
                                imageUrl = url
                            }
                            
                            if let id = idString, let url = imageUrl {
                                let name = symbolDict["name"] as? String
                                results.append(SymbolResult(id: id, image_url: url, name: name))
                            }
                        }
                        
                        if !results.isEmpty {
                            await MainActor.run {
                                self.searchResults = results
                            }
                            return results
                        }
                    }
                }
                
                // If it's an array of dictionaries, try manual parsing
                if let array = jsonObject as? [[String: Any]] {
                    var results: [SymbolResult] = []
                    for symbolDict in array {
                        var idString: String?
                        var imageUrl: String?
                        
                        // Get id
                        if let id = symbolDict["id"] as? String {
                            idString = id
                        } else if let id = symbolDict["id"] as? Int {
                            idString = String(id)
                        }
                        
                        // Get image URL
                        if let url = symbolDict["image_url"] as? String {
                            imageUrl = url
                        } else if let url = symbolDict["imageUrl"] as? String {
                            imageUrl = url
                        } else if let url = symbolDict["image"] as? String {
                            imageUrl = url
                        }
                        
                        if let id = idString, let url = imageUrl {
                            let name = symbolDict["name"] as? String
                            results.append(SymbolResult(id: id, image_url: url, name: name))
                        }
                    }
                    
                    if !results.isEmpty {
                        await MainActor.run {
                            self.searchResults = results
                        }
                        return results
                    }
                }
                
                let errorMsg = "Failed to parse response. Format: \(type(of: jsonObject))"
                print("Final parse error: \(errorMsg)")
                await MainActor.run {
                    self.errorMessage = errorMsg
                }
                throw NSError(domain: "OpenSymbolsService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(arrayError.localizedDescription)"])
            }
        }
    }
    
    // Download image from URL
    func downloadImage(from urlString: String) async throws -> UIImage? {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "OpenSymbolsService", code: -6, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    }
}

