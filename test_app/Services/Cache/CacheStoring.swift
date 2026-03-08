import Foundation

protocol CacheStoring {
    func save(accounts: [Account])
    func save(transactions: [Transaction])
    func loadAccounts() -> [Account]
    func loadTransactions() -> [Transaction]
}

final class InMemoryCacheStore: CacheStoring {
    private var accounts: [Account] = []
    private var transactions: [Transaction] = []

    func save(accounts: [Account]) {
        self.accounts = accounts
    }

    func save(transactions: [Transaction]) {
        self.transactions = transactions
    }

    func loadAccounts() -> [Account] {
        accounts
    }

    func loadTransactions() -> [Transaction] {
        transactions
    }
}
