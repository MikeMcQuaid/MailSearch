import NIOIMAPCore

public extension IMAPServer {
    func loginWithPassword(username: String, password: String) async throws {
        if capabilities.contains(.authenticate(AuthenticationMechanism("PLAIN"))) {
            try await authenticatePlain(username: username, password: password)
        } else {
            guard !capabilities.contains(.loginDisabled) else {
                throw IMAPError.unsupportedAuthMechanism("No supported password authentication method")
            }
            try await login(username: username, password: password)
        }
    }
}
