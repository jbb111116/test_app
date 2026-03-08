import Foundation
//test comment
enum IntegrationConfigKey: String, CaseIterable {
    case plaidClientID = "PLAID_CLIENT_ID"
    case plaidSecret = "PLAID_SECRET"
    case plaidEnvironment = "PLAID_ENVIRONMENT"
    case tellerApplicationID = "TELLER_APPLICATION_ID"
    case tellerSigningSecret = "TELLER_SIGNING_SECRET"
    case tellerEnvironment = "TELLER_ENVIRONMENT"
}

protocol IntegrationConfigurationProviding {
    func string(for key: IntegrationConfigKey) -> String?
}

struct BundleIntegrationConfigurationProvider: IntegrationConfigurationProviding {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func string(for key: IntegrationConfigKey) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key.rawValue) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PlaidConfiguration {
    let clientID: String
    let secret: String
    let environment: String

    static func from(_ provider: IntegrationConfigurationProviding) -> PlaidConfiguration? {
        guard
            let clientID = provider.string(for: .plaidClientID),
            let secret = provider.string(for: .plaidSecret),
            let environment = provider.string(for: .plaidEnvironment)
        else {
            return nil
        }

        return PlaidConfiguration(clientID: clientID, secret: secret, environment: environment)
    }
}

struct TellerConfiguration {
    let applicationID: String
    let signingSecret: String
    let environment: String

    static func from(_ provider: IntegrationConfigurationProviding) -> TellerConfiguration? {
        guard
            let applicationID = provider.string(for: .tellerApplicationID),
            let signingSecret = provider.string(for: .tellerSigningSecret),
            let environment = provider.string(for: .tellerEnvironment)
        else {
            return nil
        }

        return TellerConfiguration(applicationID: applicationID, signingSecret: signingSecret, environment: environment)
    }
}
