import NIOIMAPCore

public extension IMAPServer {
    /// Authenticates with the password mechanism advertised by the server.
    func loginWithPassword(username: String, password: String) async throws {
        if capabilities.contains(.authenticate(AuthenticationMechanism("PLAIN"))) {
            try await authenticatePlain(username: username, password: password)
        } else {
            guard capabilities.contains(.loginDisabled) == false else {
                throw IMAPError.unsupportedAuthMechanism("No supported password authentication method")
            }

            try await login(username: username, password: password)
        }
    }
}
