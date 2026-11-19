import Foundation

let configuration = Configuration(baseURL: try Configuration.serverURL("https://gitlab.example.com/"), username: "alice")
let selfManaged = Configuration(baseURL: try Configuration.serverURL(" GitLab.Example.org:8443/forge/ "), username: "bob")
try verifyLocalBehavior(configuration: configuration, selfManaged: selfManaged)

let completed = DispatchSemaphore(value: 0)
Task.detached {
    do {
        try await verifyGitLabAPI(configuration: configuration, selfManaged: selfManaged)
        try await verifyConnectionLifecycle()
        print("Passed: account switching and recovery, live language changes, language persistence, and sign-out with Keychain error handling.")
        try await verifyMutationCompletion()
        print("Passed: unconfirmed and unassigned creations, duplicate-free verification retries, and close-before-refresh for create, update and delete.")
    } catch { fatalError("Mock API test failed: \(error)") }
    completed.signal()
}
let deadline = Date().addingTimeInterval(30)
while completed.wait(timeout: .now()) != .success {
    precondition(Date() < deadline, "Timed out waiting for the mock tests")
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
print("Passed: API decoding and filters, blocker directions, closed blockers, HTTPS/origin checks, redirect rejection, cookie-free sessions, disabled disk cache and credential storage.")
