import Foundation

protocol BankingAPI {
    func fetchAccounts() async throws -> [Account]
    func fetchTransactions() async throws -> [Transaction]
}

enum BankingIntegrationError: Error {
    case notImplemented(provider: APIProvider)
}

protocol PlaidSDKClient {
    func createLinkToken() async throws -> String
}

protocol TellerSDKClient {
    func createEnrollmentToken() async throws -> String
}

struct PlaidSDKStubClient: PlaidSDKClient {
    let configuration: PlaidConfiguration?

    func createLinkToken() async throws -> String {
        // Stub for future Plaid SDK wiring. Uses config when available.
        if configuration != nil {
            return "plaid-link-token-stub"
        }
        return "plaid-link-token-stub-unconfigured"
    }
}

struct TellerSDKStubClient: TellerSDKClient {
    let configuration: TellerConfiguration?

    func createEnrollmentToken() async throws -> String {
        // Stub for future Teller SDK wiring. Uses config when available.
        if configuration != nil {
            return "teller-enrollment-token-stub"
        }
        return "teller-enrollment-token-stub-unconfigured"
    }
}

struct PlaidAPI: BankingAPI {
    private let sdkClient: any PlaidSDKClient

    init(sdkClient: any PlaidSDKClient) {
        self.sdkClient = sdkClient
    }

    func fetchAccounts() async throws -> [Account] {
        _ = try await sdkClient.createLinkToken()
        return MockData.plaidAccounts
    }

    func fetchTransactions() async throws -> [Transaction] {
        _ = try await sdkClient.createLinkToken()
        return MockData.plaidTransactions
    }
}

struct TellerAPI: BankingAPI {
    private let sdkClient: any TellerSDKClient

    init(sdkClient: any TellerSDKClient) {
        self.sdkClient = sdkClient
    }

    func fetchAccounts() async throws -> [Account] {
        _ = try await sdkClient.createEnrollmentToken()
        return MockData.tellerAccounts
    }

    func fetchTransactions() async throws -> [Transaction] {
        _ = try await sdkClient.createEnrollmentToken()
        return MockData.tellerTransactions
    }
}
