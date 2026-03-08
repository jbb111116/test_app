import Foundation

protocol BankingAPI {
    func fetchAccounts() async throws -> [Account]
    func fetchTransactions() async throws -> [Transaction]
}

enum BankingIntegrationError: LocalizedError {
    case missingConfiguration(provider: APIProvider)
    case notImplemented(provider: APIProvider)
    case authenticationFailed(provider: APIProvider)
    case timeout(provider: APIProvider)
    case rateLimited(provider: APIProvider)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let provider):
            return "Missing configuration for \(provider.rawValue.capitalized) integration."
        case .notImplemented(let provider):
            return "\(provider.rawValue.capitalized) data sync is not implemented yet."
        case .authenticationFailed(let provider):
            return "\(provider.rawValue.capitalized) authentication failed."
        case .timeout(let provider):
            return "\(provider.rawValue.capitalized) request timed out."
        case .rateLimited(let provider):
            return "\(provider.rawValue.capitalized) rate limit exceeded."
        }
    }
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
        guard configuration != nil else {
            throw BankingIntegrationError.missingConfiguration(provider: .plaid)
        }
        return "plaid-link-token-stub"
    }
}

struct TellerSDKStubClient: TellerSDKClient {
    let configuration: TellerConfiguration?

    func createEnrollmentToken() async throws -> String {
        guard configuration != nil else {
            throw BankingIntegrationError.missingConfiguration(provider: .teller)
        }
        return "teller-enrollment-token-stub"
    }
}

struct MockAPI: BankingAPI {
    func fetchAccounts() async throws -> [Account] {
        MockBankingData.accounts
    }

    func fetchTransactions() async throws -> [Transaction] {
        MockBankingData.transactions
    }
}

struct PlaidAPI: BankingAPI {
    private let sdkClient: any PlaidSDKClient

    init(sdkClient: any PlaidSDKClient) {
        self.sdkClient = sdkClient
    }

    func fetchAccounts() async throws -> [Account] {
        _ = try await sdkClient.createLinkToken()
        throw BankingIntegrationError.notImplemented(provider: .plaid)
    }

    func fetchTransactions() async throws -> [Transaction] {
        _ = try await sdkClient.createLinkToken()
        throw BankingIntegrationError.notImplemented(provider: .plaid)
    }
}

struct TellerAPI: BankingAPI {
    private let sdkClient: any TellerSDKClient

    init(sdkClient: any TellerSDKClient) {
        self.sdkClient = sdkClient
    }

    func fetchAccounts() async throws -> [Account] {
        _ = try await sdkClient.createEnrollmentToken()
        throw BankingIntegrationError.notImplemented(provider: .teller)
    }

    func fetchTransactions() async throws -> [Transaction] {
        _ = try await sdkClient.createEnrollmentToken()
        throw BankingIntegrationError.notImplemented(provider: .teller)
    }
}

enum MockBankingData {
    static let accounts: [Account] = [
        Account(name: "Mock Checking", type: "Checking", balance: 3900.45),
        Account(name: "Mock Savings", type: "Savings", balance: 12800.20),
        Account(name: "Mock Brokerage", type: "Investment", balance: 25100.75),
        Account(name: "Mock Rewards Card", type: "Credit Card", balance: -1730.10),
        Account(name: "Mock Student Loan", type: "Loan", balance: -16420.00),
        Account(name: "Mock Auto Loan", type: "Loan", balance: -8400.55)
    ]

    static let transactions: [Transaction] = [
        Transaction(merchant: "Employer Payroll", category: "Income", amount: 4200.00, date: Date()),
        Transaction(merchant: "Acme Grocery", category: "", amount: -184.36, date: Date()),
        Transaction(merchant: "Uber", category: "", amount: -29.75, date: Date()),
        Transaction(merchant: "Card Payment", category: "Credit Card", amount: -600.00, date: Date()),
        Transaction(merchant: "Student Loan Servicing", category: "Loan Payment", amount: -320.00, date: Date()),
        Transaction(merchant: "Auto Loan Servicing", category: "Loan Payment", amount: -285.50, date: Date()),
        Transaction(merchant: "Brokerage Deposit", category: "Investment", amount: -450.00, date: Date()),
        Transaction(merchant: "Whole Market Grocery", category: "", amount: -143.90, date: Date())
    ]
}
