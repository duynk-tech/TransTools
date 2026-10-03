#!/usr/bin/env python3
"""Compile the production AI transport and verify requests, parsing and retry boundaries.
--live sends a short synthetic prompt using locally configured keys, never prints keys.
"""
from pathlib import Path
import subprocess, tempfile, sys
root=Path(__file__).resolve().parent.parent
services=(root/'Sources/TransTools/Services.swift').read_text()
provider=services[services.index('enum AIProvider:'):services.index('// MARK: - Supported Translation')]
transport=(root/'Sources/TransTools/AITransport.swift').read_text()
code='import Foundation\nimport CryptoKit\nimport IOKit\nimport Security\n'+provider+transport
if '--live' in sys.argv:
    conversation=services[services.index('    static func practiceConversation('):services.index('    static func summarizeMeeting(')].replace('try await callAI(', 'try await AITransport.complete(')
    code += 'enum ConversationHarness {\n' + conversation + '}\n'
    code+='''
@main struct Main {
 static func main() async {
  var failed = false
  for provider in [AIProvider.gemini, .openai, .deepseek, .claude] {
   let key = CredentialStore.read(for: provider)
   guard !key.isEmpty else { print("SKIP \\(provider.shortName): no configured key"); continue }
   do {
    let models = try await AITransport.models(provider: provider, key: key)
    print("LIVE \\(provider.shortName): \\(models.count) text models; preferred \\(models.first!)")
    let saved = UserDefaults(suiteName: "local.mactools.transtools")!.string(forKey: "AIModel_\\(provider.rawValue)") ?? provider.defaultModel
    let reply = try await AITransport.complete(prompt: "Reply with exactly: Hello! How are you today?", provider: provider, model: saved, key: key)
    print("PASS LIVE \\(provider.shortName): \\(reply.prefix(180))")
    let practice = try await ConversationHarness.practiceConversation(history: "Bạn: Hello, how are you?", language: "English", level: "A2", goal: "Daily communication", provider: provider, model: saved, key: key)
    print("PASS CONVERSATION \\(provider.shortName): \\(practice.reply.prefix(250))")
   } catch { failed = true; print("FAIL LIVE \\(provider.shortName): \\(error.localizedDescription)") }
  }
  if failed { exit(1) }
 }
}
'''
else:
    code+='''
final class MockProtocol: URLProtocol {
 static var responses: [(Int, [String: Any])] = []
 static var requests: [URLRequest] = []
 static var stall = false
 static var stopped = false
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  Self.requests.append(request)
  if Self.stall { return }
  let (status, object) = Self.responses.removeFirst()
  client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
  client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() { Self.stopped = true }
}
func check(_ ok: Bool, _ label: String) { precondition(ok, label); print("PASS: " + label) }
@main struct Main {
 static func main() async throws {
  let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
  let session = URLSession(configuration: config)
  for provider in [AIProvider.gemini, .openai, .deepseek, .claude] {
   let req = try AITransport.completionRequest(prompt: "hello", provider: provider, model: provider.defaultModel, key: "test-secret")
   let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
   check(req.httpMethod == "POST" && !req.url!.absoluteString.contains("test-secret"), "\\(provider.shortName) POST, secret excluded from URL")
   check(body["temperature"] == nil, "\\(provider.shortName) no unsupported sampling parameter")
   if provider == .openai { check(body["max_completion_tokens"] != nil && body["max_tokens"] == nil, "OpenAI reasoning token parameter") }
   if provider == .gemini { check(req.value(forHTTPHeaderField: "x-goog-api-key") == "test-secret", "Gemini header authentication") }
   if provider == .claude { check(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Claude version header") }
  }
  let responseReq = try AITransport.completionRequest(prompt: "hello", provider: .openai, model: "gpt-6-astra", key: "test")
  let responseBody = try JSONSerialization.jsonObject(with: responseReq.httpBody!) as! [String: Any]
  check(responseReq.url!.path == "/v1/responses" && responseBody["input"] as? String == "hello" && responseBody["store"] as? Bool == false, "OpenAI new models use Responses without storing state")
  let output: [String: Any] = ["output": [["type": "reasoning", "content": []], ["type": "message", "content": [["type": "output_text", "text": "Hello"], ["type": "output_text", "text": " world"]]]]]
  check(try AITransport.output(output, provider: .openai) == "Hello world", "OpenAI Responses collects output text after reasoning")
  check(!AITransport.supportsText("gpt-realtime", provider: .openai) && !AITransport.supportsText("gemini-tts", provider: .gemini), "exclude non-text models")
  let gem: [String: Any] = ["candidates": [["content": ["parts": [["text": "private thought", "thought": true], ["text": "Hello "], ["text": "world"]]]]]]
  check(try AITransport.output(gem, provider: .gemini) == "Hello world", "Gemini combines all text parts and ignores thoughts")
  check(try AITransport.output(["content": [["type": "thinking", "thinking": "hidden"], ["type": "text", "text": "Hello"]]], provider: .claude) == "Hello", "Claude text blocks after thinking")
  let success: [String: Any] = ["choices": [["message": ["content": "Hello"]]]]
  for provider in [AIProvider.openai, .deepseek] { check(try AITransport.output(success, provider: provider) == "Hello", "\\(provider.shortName) chat result") }
  MockProtocol.responses = [(200, ["models": [["name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]]], "nextPageToken": "next"]), (200, ["models": [["name": "models/gemini-embedding", "supportedGenerationMethods": ["embedContent"]], ["name": "models/gemini-3.8-pro", "supportedGenerationMethods": ["generateContent"]]]])]
  let models = try await AITransport.models(provider: .gemini, key: "test", session: session)
  check(models.count == 2 && models.first == "gemini-3.8-flash" && MockProtocol.requests.last!.url!.absoluteString.contains("pageToken=next"), "model pagination and generation capability")
  MockProtocol.requests = []
  MockProtocol.responses = [(404, ["error": ["message": "retired"]]), (200, ["models": [["name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]]]]), (200, gem)]
  let answer = try await AITransport.complete(prompt: "hello", provider: .gemini, model: "gemini-2.5-flash", key: "test", session: session)
  check(answer == "Hello world" && MockProtocol.requests.first!.url!.absoluteString.contains("gemini-2.5-flash") && MockProtocol.requests.last!.url!.absoluteString.contains("gemini-3.8-flash"), "preserve selected model; recover 404 using discovered model")
  MockProtocol.requests = []; MockProtocol.responses = [(200, gem)]
  _ = try await AITransport.complete(prompt: "next turn", provider: .gemini, model: "gemini-2.5-flash", key: "test", session: session)
  check(MockProtocol.requests.count == 1 && MockProtocol.requests.first!.url!.absoluteString.contains("gemini-3.8-flash"), "next turn reuses successful resolved model")
  MockProtocol.requests = []; MockProtocol.responses = [(200, ["data": [["id": "claude-haiku-4-5"]], "has_more": true, "last_id": "claude-haiku-4-5"]), (200, ["data": [["id": "claude-sonnet-5-5"]], "has_more": false])]
  let claudeModels = try await AITransport.models(provider: .claude, key: "test", session: session)
  check(claudeModels.count == 2 && MockProtocol.requests.last!.url!.absoluteString.contains("after_id="), "Claude model pagination")
  MockProtocol.responses = [(401, ["error": ["message": "invalid key"]])]
  do { _ = try await AITransport.models(provider: .deepseek, key: "test", session: session); fatalError("expected discovery error") }
  catch { check((error as NSError).code == 401, "DeepSeek discovery does not hide invalid key behind defaults") }
  let structured = try PracticeConversationReply.parse("{\\"reply\\":\\"Hello!\\",\\"feedback\\":\\"\\"}")
  check(structured.reply == "Hello!" && structured.feedback.isEmpty, "typed conversation reply")
  for invalid in ["Hello! GÓP Ý: no schema", "{\\"reply\\":\\" \\",\\"feedback\\":\\"\\"}", "{\\"reply\\":42}"] {
   do { _ = try PracticeConversationReply.parse(invalid); fatalError("expected schema error") }
   catch { check(true, "reject malformed conversation reply") }
  }
  for code in [400, 401, 403, 429, 500] {
   MockProtocol.requests = []; MockProtocol.responses = [(code, ["error": ["message": "failure"]])]
   do { _ = try await AITransport.complete(prompt: "hello", provider: .gemini, model: "gemini-3.8-flash", key: "test", session: session); fatalError("expected error") }
   catch { check((error as NSError).code == code && MockProtocol.requests.count == 1, "no model retries for HTTP \\(code)") }
  }
  MockProtocol.stall = true; MockProtocol.stopped = false
  let started = Date()
  do { _ = try await AITransport.complete(prompt: "hello", provider: .gemini, model: "gemini-3.8-flash", key: "test", session: session, timeout: 1); fatalError("expected timeout") }
  catch { check((error as NSError).code == URLError.timedOut.rawValue && Date().timeIntervalSince(started) < 3, "whole AI task deadline") }
  check(MockProtocol.stopped, "deadline cancels network request")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='transtools-ai-') as tmp:
    source=Path(tmp)/'Harness.swift'; source.write_text(code)
    binary=Path(tmp)/'harness'
    subprocess.run(['swiftc','-parse-as-library',str(source),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
