import Foundation
import Testing
@testable import test_app

@MainActor
struct test_appTests {

    @Test func refreshData_usesInjectedBankingFactory() async throws {
        final class SpyAPI: BankingAPI {
            func fetchAccounts() async throws -> [Account] {
                [Account(name: "Injected", type: "Checking", balance: 10)]
            }

            func fetchTransactions() async throws -> [Transaction] {
                [Transaction(merchant: "Injected Merchant", category: "", amount: -1, date: Date())]
            }
        }

        var selectedProvider: APIProvider?
        let dependencies = AppDependencies(
            makeBankingAPI: { provider in
                selectedProvider = provider
                return SpyAPI()
            },
            cacheStore: InMemoryCacheStore(),
            makeLogger: { _ in TestLogger() }
        )

        let config = AppConfig()
        config.apiProvider = .teller
        let viewModel = AppViewModel(config: config, dependencies: dependencies)

        await viewModel.refreshData()

        #expect(selectedProvider == .teller)
        #expect(viewModel.accounts.count == 1)
        #expect(viewModel.transactions.first?.category == "Misc")
    }
}

private final class TestLogger: Logger {
    func log(_ message: String) {}
    func error(_ message: String) {}
}
