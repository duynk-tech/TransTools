import XCTest
@testable import TransTools

private final class AssistantMockProtocol: URLProtocol {
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let quota = request.value(forHTTPHeaderField: "Authorization") == "Bearer quota-test"
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: quota ? 429 : 200,
                                           httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let body = quota ? "{\"error\":{\"message\":\"Quota exhausted\"}}" : "{\"choices\":[{\"message\":{\"content\":\"late response\"}}]}"
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        pending = work
        DispatchQueue.global().asyncAfter(deadline: .now() + (quota ? 0 : 5), execute: work)
    }
    override func stopLoading() { pending?.cancel(); pending = nil }
}

final class MeetingAssistantTransportTests: XCTestCase {
    @MainActor func testMainActorStaysResponsiveWhileAssistantWaitsForAI() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let request = Task {
            try await AITransport.complete(prompt: "test", provider: .openai, model: "gpt-test", key: "heartbeat-test", session: session, timeout: 20)
        }
        defer { request.cancel() }
        var longestWakeDelay = 0.0
        for _ in 0..<30 {
            let before = Date()
            try await Task.sleep(nanoseconds: 10_000_000)
            longestWakeDelay = max(longestWakeDelay, Date().timeIntervalSince(before) - 0.01)
        }
        request.cancel()
        _ = try? await request.value
        print("Assistant main-actor maximum wake delay: \(Int(longestWakeDelay * 1000)) ms")
        XCTAssertLessThan(longestWakeDelay, 0.2, "Waiting for AI must yield the UI actor")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssistantMockProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testSlowProviderTimesOutWithinAssistantBudget() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        let started = Date()
        do {
            _ = try await AITransport.complete(prompt: "test", provider: .openai, model: "gpt-test", key: "timeout-test", session: session, timeout: 1)
            XCTFail("A slow provider must not leave the assistant busy indefinitely")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }

    func testHiddenPanelCancellationDoesNotWaitForLateResponse() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let started = Date()
        let task = Task {
            try await AITransport.complete(prompt: "test", provider: .openai, model: "gpt-test", key: "cancel-test", session: session, timeout: 20)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled requests must not return late text") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testQuotaErrorIsReturnedWithoutTryingAnotherModel() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AITransport.complete(prompt: "test", provider: .openai, model: "gpt-test", key: "quota-test", session: session, timeout: 2)
            XCTFail("Quota errors must reach the assistant")
        } catch { XCTAssertEqual((error as NSError).code, 429) }
    }
}
