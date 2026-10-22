import CryptoKit
import Foundation

public struct AccountIdentity: Codable, Equatable, Sendable {
    public var provider: ProviderID
    public var accountID: String
    public var workspaceID: String?
    public var displayName: String
    public var workspaceName: String?
    public var profile: String?

    public init(provider: ProviderID, accountID: String, workspaceID: String? = nil, displayName: String, workspaceName: String? = nil, profile: String? = nil) {
        self.provider = provider; self.accountID = accountID; self.workspaceID = workspaceID
        self.displayName = displayName; self.workspaceName = workspaceName
        self.profile = profile
    }
    public var scope: String {
        let parts = [provider.rawValue, accountID, workspaceID ?? "", profile ?? ""]
        let value = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}

public struct AccountUsage: Codable, Equatable, Sendable {
    public var identity: AccountIdentity?
    public var snapshot: UsageSnapshot
    public init(identity: AccountIdentity?, snapshot: UsageSnapshot) {
        self.identity = identity; self.snapshot = snapshot
    }
}
