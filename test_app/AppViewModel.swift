import Combine
import Foundation
import SwiftUI

// MARK: - Config

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case mock
    case plaid
    case teller
    var id: String { rawValue }
}

@Observable class AppConfig {
    var apiProvider: APIProvider = .mock
    var verboseLogging: Bool = true
    var enableCache: Bool = true
}

// MARK: - Health

enum HealthStatus: String { case ok, degraded, down }

extension HealthStatus {
    var color: Color {
        switch self {
        case .ok: return .green
        case .degraded: return .yellow
        case .down: return .red
        }
    }

    var description: String {
        switch self {
        case .ok: return "All systems nominal"
        case .degraded: return "Some checks failing"
        case .down: return "Service unavailable"
        }
    }
}

struct HealthState {
    var status: HealthStatus = .ok
    var details: [String] = []
}

// MARK: - Models

struct Account: Identifiable, Codable {
    let id = UUID()
    var name: String
    var type: String
    var balance: Decimal
    var balanceFormatted: String { CurrencyFormatter.string(from: balance) }
}

struct Transaction: Identifiable, Codable {
    let id = UUID()
    var merchant: String
    var category: String
    var amount: Decimal
    var date: Date
    var amountFormatted: String { CurrencyFormatter.string(from: amount) }
}

struct BudgetState {
    var initial: Decimal
    var current: Decimal
    var initialFormatted: String { CurrencyFormatter.string(from: initial) }
    var currentFormatted: String { CurrencyFormatter.string(from: current) }
}

struct MetricsState {
    var netWorth: Decimal = 0
    var savingsRate: Double = 0
    var investmentRate: Double = 0
    var emergencyTarget: Decimal = 0

    var netWorthFormatted: String { CurrencyFormatter.string(from: netWorth) }
    var savingsRateFormatted: String { PercentFormatter.string(from: savingsRate) }
    var investmentRateFormatted: String { PercentFormatter.string(from: investmentRate) }
    var emergencyTargetFormatted: String { CurrencyFormatter.string(from: emergencyTarget) }
}

// MARK: - Agent Placeholder

enum AgentRequest { case summary, recommendations, explainBudget }

struct AgentState {
    var summaryPlaceholder: String =
        "The assistant will analyze your spending, income, and goals to provide insights and recommendations."
}

// MARK: - App ViewModel

final class AppViewModel: ObservableObject {
    @Published var selectedSection: AppSection = .dashboard
    @Published var activeAlert: AppAlert?

    @Published var config: AppConfig

    private let dependencies: AppDependencies
    private let cache: any CacheStoring
    private lazy var logger: Logger = dependencies.makeLogger { [weak self] in
        self?.config.verboseLogging ?? false
    }

    @Published var health = HealthState()
    @Published var metrics = MetricsState()
    @Published var budget = BudgetState(initial: 2000, current: 2000)
    @Published var agent = AgentState()

    @Published var accounts: [Account] = []
    @Published var transactions: [Transaction] = []

    init(config: AppConfig = AppConfig(), dependencies: AppDependencies = .live) {
        self.config = config
        self.dependencies = dependencies
        self.cache = dependencies.cacheStore
    }

    @MainActor
    func startup() async {
        logger.log("Startup: provider=\(config.apiProvider.rawValue)")
        await runHealthCheck()
        await refreshData()
        computeMetrics()
    }

    @MainActor
    func runHealthCheck() async {
        var details: [String] = []
        details.append("Logger active: true")
        details.append("Cache enabled: \(config.enableCache)")
        details.append("API provider: \(config.apiProvider.rawValue)")
        let status: HealthStatus = .ok
        health = HealthState(status: status, details: details)
        logger.log("Health check complete: \(status.rawValue)")
    }

    @MainActor
    func refreshData() async {
        do {
            let provider = dependencies.makeBankingAPI(config.apiProvider)
            let accounts = try await provider.fetchAccounts()
            let transactions = try await provider.fetchTransactions()
            if config.enableCache {
                cache.save(accounts: accounts)
                cache.save(transactions: transactions)
            }
            self.accounts = accounts
            self.transactions = categorize(transactions)
            logger.log("Loaded accounts=\(accounts.count) transactions=\(transactions.count)")
        } catch {
            logger.error("Failed to load data: \(error)")
            activeAlert = AppAlert(title: "Data Error", message: error.localizedDescription)
            if config.enableCache {
                self.accounts = cache.loadAccounts()
                self.transactions = cache.loadTransactions()
            }
        }
    }

    private func categorize(_ txs: [Transaction]) -> [Transaction] {
        txs.map { tx in
            var category = tx.category
            if tx.merchant.lowercased().contains("grocery") {
                category = "Groceries"
            } else if tx.merchant.lowercased().contains("uber") {
                category = "Transport"
            } else if tx.amount < 0 && category.isEmpty {
                category = "Misc"
            }
            return Transaction(
                merchant: tx.merchant, category: category, amount: tx.amount, date: tx.date)
        }
    }

    func budgetIncrease(byPercent p: Double) {
        let factor = Decimal(1 + p / 100)
        budget.current *= factor
        logger.log("Budget increased by \(p)% -> \(budget.current)")
    }

    func budgetDecrease(byPercent p: Double) {
        let factor = Decimal(1 - p / 100)
        budget.current *= factor
        logger.log("Budget decreased by \(p)% -> \(budget.current)")
    }

    func computeMetrics() {
        let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.balance }
        let income = transactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        let expenses = transactions.filter { $0.amount < 0 }.reduce(Decimal(0)) {
            $0 + abs($1.amount)
        }
        let totalIn = (income as NSDecimalNumber).doubleValue
        let totalOut = (expenses as NSDecimalNumber).doubleValue
        let savingsRate = totalIn == 0 ? 0 : max(0, (totalIn - totalOut) / totalIn)
        let investmentRate = min(0.5, savingsRate * 0.6)
        let monthlyExpenses = totalOut / 3.0
        let emergencyTarget = Decimal(monthlyExpenses * 3.0)

        metrics = MetricsState(
            netWorth: netWorth,
            savingsRate: savingsRate,
            investmentRate: investmentRate,
            emergencyTarget: emergencyTarget
        )
    }

    @MainActor
    func agentRequest(_ request: AgentRequest) async {
        switch request {
        case .summary:
            activeAlert = AppAlert(
                title: "Summary",
                message:
                    "Net worth: \(metrics.netWorthFormatted)\nSavings rate: \(metrics.savingsRateFormatted)"
            )
        case .recommendations:
            activeAlert = AppAlert(
                title: "Recommendations",
                message:
                    "Consider increasing your emergency fund to \(metrics.emergencyTargetFormatted) and raising investment rate to \(PercentFormatter.string(from: min(0.5, metrics.investmentRate + 0.05)))."
            )
        case .explainBudget:
            activeAlert = AppAlert(
                title: "Budget Policy",
                message:
                    "The initial budget sets a floor. Adjustments are only allowed upward to encourage savings discipline."
            )
        }
    }
}

// MARK: - Alerts

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Formatting Helpers

enum CurrencyFormatter {
    static func string(from amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}

enum PercentFormatter {
    static func string(from value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? "0%"
    }
}
