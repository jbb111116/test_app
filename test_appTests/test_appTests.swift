import Foundation
import Testing
@testable import test_app

@MainActor
struct test_appTests {

    @Test func refreshData_usesInjectedBankingFactory() async throws {
        var selectedProvider: APIProvider?
        let dependencies = AppDependencies(
            makeBankingAPI: { provider in
                selectedProvider = provider
                return MockBankingAPI(
                    accounts: [Account(name: "Injected", type: "Checking", balance: 10)],
                    transactions: [Transaction(merchant: "Injected Merchant", category: "", amount: -1, date: Date())]
                )
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .mock
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(selectedProvider == .mock)
        #expect(viewModel.accounts.count == 1)
        #expect(viewModel.transactions.first?.category == "Misc")
    }

    @Test func mockProvider_returnsRichDataset() async {
        let viewModel = AppViewModel(dependencies: .test)
        viewModel.config.apiProvider = .mock

        await viewModel.refreshData()

        #expect(viewModel.accounts.count >= 5)
        #expect(viewModel.accounts.contains(where: { $0.type == "Credit Card" }))
        #expect(viewModel.accounts.contains(where: { $0.type == "Loan" }))
        #expect(!viewModel.transactions.isEmpty)
    }

    @Test func computeMetrics_calculatesExpectedValues() {
        let viewModel = AppViewModel(dependencies: .test)
        viewModel.accounts = [
            Account(name: "Checking", type: "Checking", balance: 1000),
            Account(name: "Savings", type: "Savings", balance: 5000),
            Account(name: "Loan", type: "Loan", balance: -2000)
        ]
        viewModel.transactions = [
            Transaction(merchant: "Payroll", category: "Income", amount: 4000, date: Date()),
            Transaction(merchant: "Rent", category: "Housing", amount: -1000, date: Date()),
            Transaction(merchant: "Groceries", category: "Food", amount: -500, date: Date())
        ]

        viewModel.computeMetrics()

        #expect(decimalToDouble(viewModel.metrics.netWorth) == 4000)
        #expect(abs(viewModel.metrics.savingsRate - 0.625) < 0.0001)
        #expect(abs(viewModel.metrics.investmentRate - 0.375) < 0.0001)
        #expect(decimalToDouble(viewModel.metrics.emergencyTarget) == 1500)
    }

    @Test func budgetAdjustments_applyExpectedMath() {
        let viewModel = AppViewModel(dependencies: .test)

        viewModel.budgetIncrease(byPercent: 10)
        #expect(decimalToDouble(viewModel.budget.current) == 2200)

        viewModel.budgetDecrease(byPercent: 10)
        #expect(abs(decimalToDouble(viewModel.budget.current) - 1980) < 0.0001)
    }

    @Test func refreshData_appliesCategorizationRules() async {
        let dependencies = AppDependencies(
            makeBankingAPI: { _ in
                MockBankingAPI(
                    accounts: [],
                    transactions: [
                        Transaction(merchant: "Acme Grocery", category: "", amount: -25, date: Date()),
                        Transaction(merchant: "Uber Trip", category: "", amount: -12, date: Date()),
                        Transaction(merchant: "Unknown Merchant", category: "", amount: -5, date: Date()),
                        Transaction(merchant: "Known Category", category: "Utilities", amount: -30, date: Date())
                    ]
                )
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let viewModel = AppViewModel(dependencies: dependencies)
        await viewModel.refreshData()

        #expect(viewModel.transactions.count == 4)
        #expect(viewModel.transactions[0].category == "Groceries")
        #expect(viewModel.transactions[1].category == "Transport")
        #expect(viewModel.transactions[2].category == "Misc")
        #expect(viewModel.transactions[3].category == "Utilities")
    }

    @Test func plaidProvider_missingConfig_setsDataErrorAlert() async {
        let dependencies = AppDependencies(
            makeBankingAPI: { _ in
                PlaidAPI(sdkClient: PlaidSDKStubClient(configuration: nil))
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .plaid
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(viewModel.activeAlert?.title == "Data Error")
        #expect(viewModel.activeAlert?.message.contains("Missing configuration") == true)
    }

    @Test func plaidProvider_authFailure_setsDataErrorAlert() async {
        let dependencies = AppDependencies(
            makeBankingAPI: { _ in
                PlaidAPI(sdkClient: AuthFailingPlaidClient())
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .plaid
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(viewModel.activeAlert?.title == "Data Error")
        #expect(viewModel.activeAlert?.message.contains("authentication failed") == true)
    }

    @Test func tellerProvider_timeout_setsDataErrorAlert() async {
        let dependencies = AppDependencies(
            makeBankingAPI: { _ in
                TellerAPI(sdkClient: TimeoutTellerClient())
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .teller
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(viewModel.activeAlert?.title == "Data Error")
        #expect(viewModel.activeAlert?.message.contains("timed out") == true)
    }

    @Test func tellerProvider_rateLimited_setsDataErrorAlert() async {
        let dependencies = AppDependencies(
            makeBankingAPI: { _ in
                TellerAPI(sdkClient: RateLimitedTellerClient())
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .teller
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(viewModel.activeAlert?.title == "Data Error")
        #expect(viewModel.activeAlert?.message.contains("rate limit") == true)
    }
}

private extension AppDependencies {
    static let test = AppDependencies(
        makeBankingAPI: { provider in
            switch provider {
            case .mock:
                return MockAPI()
            case .plaid:
                return PlaidAPI(sdkClient: PlaidSDKStubClient(configuration: nil))
            case .teller:
                return TellerAPI(sdkClient: TellerSDKStubClient(configuration: nil))
            }
        },
        cacheStore: InMemoryCacheStore(),
        makeLogger: { _ in TestLogger() }
    )
}

private struct MockBankingAPI: BankingAPI {
    let accounts: [Account]
    let transactions: [Transaction]

    func fetchAccounts() async throws -> [Account] {
        accounts
    }

    func fetchTransactions() async throws -> [Transaction] {
        transactions
    }
}

private struct AuthFailingPlaidClient: PlaidSDKClient {
    func createLinkToken() async throws -> String {
        throw BankingIntegrationError.authenticationFailed(provider: .plaid)
    }
}

private struct TimeoutTellerClient: TellerSDKClient {
    func createEnrollmentToken() async throws -> String {
        throw BankingIntegrationError.timeout(provider: .teller)
    }
}

private struct RateLimitedTellerClient: TellerSDKClient {
    func createEnrollmentToken() async throws -> String {
        throw BankingIntegrationError.rateLimited(provider: .teller)
    }
}

private final class TestLogger: Logger {
    func log(_ message: String) {}
    func error(_ message: String) {}
}

private func decimalToDouble(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}
