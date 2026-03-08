import Foundation
import SwiftUI
import Combine

// MARK: - Config

enum APIProvider: String, Codable, CaseIterable, Identifiable {
    case plaid
    case teller
    var id: String { rawValue }
}

@Observable class AppConfig {
    var apiProvider: APIProvider = .plaid
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
    var summaryPlaceholder: String = "The assistant will analyze your spending, income, and goals to provide insights and recommendations."
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
            return Transaction(merchant: tx.merchant, category: category, amount: tx.amount, date: tx.date)
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
        let expenses = transactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + abs($1.amount) }
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
                message: "Net worth: \(metrics.netWorthFormatted)\nSavings rate: \(metrics.savingsRateFormatted)"
            )
        case .recommendations:
            activeAlert = AppAlert(
                title: "Recommendations",
                message: "Consider increasing your emergency fund to \(metrics.emergencyTargetFormatted) and raising investment rate to \(PercentFormatter.string(from: min(0.5, metrics.investmentRate + 0.05)))."
            )
        case .explainBudget:
            activeAlert = AppAlert(
                title: "Budget Policy",
                message: "The initial budget sets a floor. Adjustments are only allowed upward to encourage savings discipline."
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

// MARK: - Mock Data

enum MockData {
    static let plaidAccounts: [Account] = [
        Account(name: "Plaid Checking", type: "Checking", balance: 4250.12),
        Account(name: "Plaid Savings", type: "Savings", balance: 15220.49),
        Account(name: "Plaid Brokerage", type: "Investment", balance: 28340.11),
        Account(name: "Plaid Rewards Card", type: "Credit Card", balance: -1488.65),
        Account(name: "Plaid Auto Loan", type: "Loan", balance: -11240.00),
        Account(name: "Plaid Mortgage", type: "Loan", balance: -268400.00)
    ]

    static let plaidTransactions: [Transaction] = [
        Transaction(merchant: "Employer Payroll", category: "Income", amount: 4100.00, date: Date()),
        Transaction(merchant: "Acme Grocery", category: "", amount: -186.23, date: Date()),
        Transaction(merchant: "Chevron Gas", category: "Transport", amount: -74.91, date: Date()),
        Transaction(merchant: "Plaid Card Payment", category: "Credit Card", amount: -550.00, date: Date()),
        Transaction(merchant: "Auto Loan Servicer", category: "Loan Payment", amount: -420.00, date: Date()),
        Transaction(merchant: "Mortgage Lender", category: "Housing", amount: -1850.00, date: Date()),
        Transaction(merchant: "Uber", category: "", amount: -31.24, date: Date()),
        Transaction(merchant: "Savings Transfer", category: "Savings", amount: -600.00, date: Date())
    ]

    static let tellerAccounts: [Account] = [
        Account(name: "Teller Checking", type: "Checking", balance: 2980.77),
        Account(name: "Teller High-Yield Savings", type: "Savings", balance: 9430.18),
        Account(name: "Teller Retirement", type: "Investment", balance: 41880.52),
        Account(name: "Teller Travel Card", type: "Credit Card", balance: -2240.33),
        Account(name: "Teller Student Loan", type: "Loan", balance: -18490.00),
        Account(name: "Teller Personal Loan", type: "Loan", balance: -5200.50)
    ]

    static let tellerTransactions: [Transaction] = [
        Transaction(merchant: "Employer Payroll", category: "Income", amount: 3950.00, date: Date()),
        Transaction(merchant: "Whole Market Grocery", category: "", amount: -142.90, date: Date()),
        Transaction(merchant: "Coffee Collective", category: "Dining", amount: -18.45, date: Date()),
        Transaction(merchant: "Travel Card Payment", category: "Credit Card", amount: -700.00, date: Date()),
        Transaction(merchant: "Student Loan Servicing", category: "Loan Payment", amount: -310.00, date: Date()),
        Transaction(merchant: "Personal Loan Payment", category: "Loan Payment", amount: -225.50, date: Date()),
        Transaction(merchant: "Brokerage Deposit", category: "Investment", amount: -450.00, date: Date()),
        Transaction(merchant: "Uber", category: "", amount: -26.18, date: Date())
    ]
}
