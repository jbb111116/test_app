//
//  ContentView.swift
//  PersonalFinance
//
//  Created by Scaffold on 3/7/26.
//

import SwiftUI
import Combine

// Root ContentView for macOS app using MVVM architecture.
// This view hosts the high-level navigation and injects environment objects.

struct ContentView: View {
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(selected: $appViewModel.selectedSection)
                .frame(minWidth: 220)
        } detail: {
            DetailContent(selected: appViewModel.selectedSection)
                .environmentObject(appViewModel)
        }
        .task { await appViewModel.startup() }
        .alert(item: $appViewModel.activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Sidebar

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transactions = "Transactions"
    case accounts = "Accounts"
    case budgets = "Budgets"
    case settings = "Settings"

    var id: String { rawValue }
}

struct SidebarView: View {
    @Binding var selected: AppSection

    var body: some View {
        List {
            ForEach(AppSection.allCases) { section in
                Button(action: { selected = section }) {
                    HStack {
                        Text(section.rawValue)
                        Spacer()
                        if selected == section { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Finance")
    }
}

// MARK: - Detail Content

struct DetailContent: View {
    let selected: AppSection
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        switch selected {
        case .dashboard:
            DashboardView()
        case .transactions:
            TransactionsView()
        case .accounts:
            AccountsView()
        case .budgets:
            BudgetsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Dashboard and Feature Placeholder Views

struct DashboardView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Overview").font(.largeTitle).bold()

                // Health Check Status
                GroupBox("Health Check") {
                    HStack {
                        Circle()
                            .fill(app.health.status.color)
                            .frame(width: 12, height: 12)
                        Text(app.health.status.description)
                        Spacer()
                        Button("Run Now") { Task { await app.runHealthCheck() } }
                    }
                }

                // Key Metrics
                GroupBox("Key Metrics") {
                    VStack(alignment: .leading, spacing: 8) {
                        MetricRow(title: "Net Worth", value: app.metrics.netWorthFormatted)
                        MetricRow(title: "Savings Rate", value: app.metrics.savingsRateFormatted)
                        MetricRow(title: "Investment Rate", value: app.metrics.investmentRateFormatted)
                        MetricRow(title: "Emergency Fund Target", value: app.metrics.emergencyTargetFormatted)
                    }
                }

                // Agent Placeholder
                GroupBox("Assistant") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.agent.summaryPlaceholder)
                            .font(.callout)
                        HStack {
                            Button("Get Summary") { Task { await app.agentRequest(.summary) } }
                            Button("Recommendations") { Task { await app.agentRequest(.recommendations) } }
                            Button("Explain Budget") { Task { await app.agentRequest(.explainBudget) } }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }
    }
}

struct TransactionsView: View {
    @EnvironmentObject private var app: AppViewModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("Transactions").font(.title).bold()
            List(app.transactions) { tx in
                HStack {
                    Text(tx.merchant)
                    Spacer()
                    Text(tx.category)
                    Text(tx.amountFormatted)
                }
            }
        }
        .padding()
    }
}

struct AccountsView: View {
    @EnvironmentObject private var app: AppViewModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("Accounts").font(.title).bold()
            List(app.accounts) { acct in
                HStack {
                    Text(acct.name)
                    Spacer()
                    Text(acct.type)
                    Text(acct.balanceFormatted)
                }
            }
        }
        .padding()
    }
}

struct BudgetsView: View {
    @EnvironmentObject private var app: AppViewModel
    @State private var canDecrease = false // enforced upward-only adjustments

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget").font(.title).bold()
            HStack {
                Text("Initial Budget")
                Spacer()
                Text(app.budget.initialFormatted)
            }
            HStack {
                Text("Current Budget")
                Spacer()
                Text(app.budget.currentFormatted)
            }
            HStack(spacing: 12) {
                Button("Increase 5%") { app.budgetIncrease(byPercent: 5) }
                Button("Decrease 5%") { if canDecrease { app.budgetDecrease(byPercent: 5) } }
                    .disabled(!canDecrease)
                Toggle("Allow Decrease (dev)", isOn: $canDecrease)
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppViewModel

    var body: some View {
        Form {
            Picker("API Provider", selection: Binding(get: { app.config.apiProvider }, set: { app.config.apiProvider = $0 })) {
                Text("Plaid").tag(APIProvider.plaid)
                Text("Teller").tag(APIProvider.teller)
            }
            Toggle("Verbose Logging", isOn: Binding(get: { app.config.verboseLogging }, set: { app.config.verboseLogging = $0 }))
            Toggle("Enable Cache", isOn: Binding(get: { app.config.enableCache }, set: { app.config.enableCache = $0 }))
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
