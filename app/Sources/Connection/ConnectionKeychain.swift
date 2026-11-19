import Foundation
import Security

struct SavedConnection: Codable {
    let server: String
    let username: String
    let token: String
    let editingEnabled: Bool
}

enum ConnectionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.gitlab-issues-desktop.connection",
         kSecAttrAccount as String: "active"]
    }

    static func load() throws -> SavedConnection? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ConnectionError.keychain(status) }
        guard let data = result as? Data, let connection = try? JSONDecoder().decode(SavedConnection.self, from: data) else {
            throw ConnectionError.invalidTokenData
        }
        return connection
    }

    static func save(_ connection: SavedConnection) throws {
        let data = try JSONEncoder().encode(connection)
        let values = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ConnectionError.keychain(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ConnectionError.keychain(status) }
    }
}
