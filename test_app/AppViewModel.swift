//
//  AppViewModel.swift
//  PersonalFinance
//
//  Created by Scaffold on 3/7/26.
//

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

// MARK: - Logging

protocol Logger {
    func log(_ message: String)
    func error(_ message: String)
}

final class ConsoleLogger: Logger {
    let verbose: () -> Bool
    init(verbose: @escaping () -> Bool) { self.verbose = verbose }
    func log(_ message: String) {
        guard verbose() else { return }
        print("[INFO] \(message)")
    }
    func error(_ message: String) { print("[ERROR] \(message)") }
}

// MARK: - Health

enum HealthStatus: String { case ok, degraded, down }

extension HealthStatus {
    var color: Color {
        switch self { case .ok: return .green; case .degraded: return .yellow; case .down: return .red }
    }
    var description: String {
        switch self { case .ok: return "All systems nominal"; case .degraded: return "Some checks failing"; case .down: return "Service unavailable" }
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
    var type: String // Checking, Savings, Investment
    var balance: Decimal
    var balanceFormatted: String { CurrencyFormatter.string(from: balance) }
}

struct Transaction: Identifiable, Codable {
    let id = UUID()
    var merchant: String
    var category: String
    var amount: Decimal // negative for expense, positive for income
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

// MARK: - API Abstractions

protocol BankingAPI {
    func fetchAccounts() async throws -> [Account]
    func fetchTransactions() async throws -> [Transaction]
}

struct PlaidAPI: BankingAPI {
    func fetchAccounts() async throws -> [Account] { MockData.accounts }
    func fetchTransactions() async throws -> [Transaction] { MockData.transactions }
}

struct TellerAPI: BankingAPI {
    func fetchAccounts() async throws -> [Account] { MockData.accounts }
    func fetchTransactions() async throws -> [Transaction] { MockData.transactions }
}

// MARK: - Cache Placeholder (SQLite planned)

final class CacheStore {
    private var accounts: [Account] = []
    private var transactions: [Transaction] = []

    func save(accounts: [Account]) { self.accounts = accounts }
    func save(transactions: [Transaction]) { self.transactions = transactions }
    func loadAccounts() -> [Account] { accounts }
    func loadTransactions() -> [Transaction] { transactions }
}

final class SQLiteCacheStore {
    private var accounts: [Account] = []
    private var transactions: [Transaction] = []

    func save(accounts: [Account]) { self.accounts = accounts }
    func save(transactions: [Transaction]) { self.transactions = transactions }
    func loadAccounts() -> [Account] { accounts }
    func loadTransactions() -> [Transaction] { transactions }
}

// MARK: - App ViewModel

final class AppViewModel: ObservableObject {
    // UI
    @Published var selectedSection: AppSection = .dashboard
    @Published var activeAlert: AppAlert?

    // Config & infra
    @Published var config = AppConfig()
    private lazy var logger: Logger = ConsoleLogger { [weak self] in self?.config.verboseLogging ?? false }
    private let cache = FinanceSQLiteCacheStore()

    // State
    @Published var health = HealthState()
    @Published var metrics = MetricsState()
    @Published var budget = BudgetState(initial: 2000, current: 2000)
    @Published var agent = AgentState()

    @Published var accounts: [Account] = []
    @Published var transactions: [Transaction] = []

    // Lifecycle
    @MainActor
    func startup() async {
        logger.log("Startup: provider=\(config.apiProvider.rawValue)")
        await runHealthCheck()
        await refreshData()
        computeMetrics()
    }

    // Health Check
    @MainActor
    func runHealthCheck() async {
        var details: [String] = []
        // Pseudo checks
        details.append("Logger active: true")
        details.append("Cache enabled: \(config.enableCache)")
        details.append("API provider: \(config.apiProvider.rawValue)")
        let status: HealthStatus = .ok
        health = HealthState(status: status, details: details)
        logger.log("Health check complete: \(status.rawValue)")
    }

    // Data
    private func api() -> BankingAPI {
        switch config.apiProvider { case .plaid: return PlaidAPI(); case .teller: return TellerAPI() }
    }

    @MainActor
    func refreshData() async {
        do {
            let provider = api()
            let accounts = try await provider.fetchAccounts()
            let transactions = try await provider.fetchTransactions()
            if config.enableCache { cache.save(accounts: accounts); cache.save(transactions: transactions) }
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

    // Categorization (simple placeholder)
    private func categorize(_ txs: [Transaction]) -> [Transaction] {
        txs.map { tx in
            var category = tx.category
            if tx.merchant.lowercased().contains("grocery") { category = "Groceries" }
            else if tx.merchant.lowercased().contains("uber") { category = "Transport" }
            else if tx.amount < 0 && category.isEmpty { category = "Misc" }
            return Transaction(merchant: tx.merchant, category: category, amount: tx.amount, date: tx.date)
        }
    }

    // Budget rules
    func budgetIncrease(byPercent p: Double) {
        let factor = Decimal(1 + p/100)
        budget.current *= factor
        logger.log("Budget increased by \(p)% -> \(budget.current)")
    }

    func budgetDecrease(byPercent p: Double) {
        // Allowed only via dev flag in UI; rule is upward-only otherwise.
        let factor = Decimal(1 - p/100)
        budget.current *= factor
        logger.log("Budget decreased by \(p)% -> \(budget.current)")
    }

    // Metrics
    func computeMetrics() {
        let netWorth = accounts.reduce(Decimal(0)) { $0 + $1.balance }
        let income = transactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
        let expenses = transactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + abs($1.amount) }
        let totalIn = (income as NSDecimalNumber).doubleValue
        let totalOut = (expenses as NSDecimalNumber).doubleValue
        let savingsRate = totalIn == 0 ? 0 : max(0, (totalIn - totalOut) / totalIn)
        let investmentRate = min(0.5, savingsRate * 0.6) // placeholder heuristic

        // Emergency target: 3 months of expenses (placeholder)
        let monthlyExpenses = totalOut / 3.0
        let emergencyTarget = Decimal(monthlyExpenses * 3.0)

        metrics = MetricsState(netWorth: netWorth, savingsRate: savingsRate, investmentRate: investmentRate, emergencyTarget: emergencyTarget)
    }

    // Agent actions (placeholder)
    @MainActor
    func agentRequest(_ request: AgentRequest) async {
        switch request {
        case .summary:
            activeAlert = AppAlert(title: "Summary", message: "Net worth: \(metrics.netWorthFormatted)\nSavings rate: \(metrics.savingsRateFormatted)")
        case .recommendations:
            activeAlert = AppAlert(title: "Recommendations", message: "Consider increasing your emergency fund to \(metrics.emergencyTargetFormatted) and raising investment rate to \(PercentFormatter.string(from: min(0.5, metrics.investmentRate + 0.05))).")
        case .explainBudget:
            activeAlert = AppAlert(title: "Budget Policy", message: "The initial budget sets a floor. Adjustments are only allowed upward to encourage savings discipline.")
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
    static let accounts: [Account] = [
        Account(name: "Checking", type: "Checking", balance: 3200),
        Account(name: "Savings", type: "Savings", balance: 8400),
        Account(name: "Brokerage", type: "Investment", balance: 12500)
    ]

    static let transactions: [Transaction] = [
        Transaction(merchant: "Acme Grocery", category: "", amount: -120.45, date: Date()),
        Transaction(merchant: "Employer Payroll", category: "Income", amount: 3200, date: Date()),
        Transaction(merchant: "Uber", category: "", amount: -22.90, date: Date()),
        Transaction(merchant: "Brokerage Deposit", category: "Investment", amount: -300, date: Date())
    ]
}

