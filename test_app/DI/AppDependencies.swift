import Foundation

struct AppDependencies {
    let makeBankingAPI: (APIProvider) -> BankingAPI
    let cacheStore: any CacheStoring
    let makeLogger: (@escaping () -> Bool) -> Logger

    static let live = AppDependencies(
        makeBankingAPI: { provider in
            let configurationProvider = BundleIntegrationConfigurationProvider()

            switch provider {
            case .plaid:
                let plaidConfig = PlaidConfiguration.from(configurationProvider)
                let plaidStub = PlaidSDKStubClient(configuration: plaidConfig)
                return PlaidAPI(sdkClient: plaidStub)
            case .teller:
                let tellerConfig = TellerConfiguration.from(configurationProvider)
                let tellerStub = TellerSDKStubClient(configuration: tellerConfig)
                return TellerAPI(sdkClient: tellerStub)
            }
        },
        cacheStore: FinanceSQLiteCacheStore(),
        makeLogger: { isVerbose in
            ConsoleLogger(verbose: isVerbose)
        }
    )
}
