import Foundation

/// Provider-specific text APIs. Model discovery never substitutes an old hardcoded model.
private actor AIModelResolution {
    static let shared = AIModelResolution()
    private var values: [String: String] = [:]
    func get(_ id: String) -> String? { values[id] }
    func set(_ id: String, model: String) {
        if values.count > 64 { values.removeAll() }
        values[id] = model
    }
}

enum AITransport {
    static let modelResolved = Notification.Name("TransToolsAIModelResolved")
    static func resolvedModel(provider: AIProvider, model: String, key: String) async -> String {
        await AIModelResolution.shared.get(provider.rawValue + "|" + model + "|" + key) ?? model
    }
    static func supportsText(_ id: String, provider: AIProvider) -> Bool {
        let name = id.lowercased()
        let excluded = ["embedding", "image", "vision-only", "tts", "audio", "realtime", "transcribe", "whisper", "aqa", "robotics", "omni", "computer-use", "deep-research", "codex", "moderation"]
        guard !excluded.contains(where: name.contains) else { return false }
        switch provider {
        case .gemini: return name.hasPrefix("gemini-") && !name.contains("live")
        case .openai: return name.hasPrefix("gpt-") || ["o1", "o3", "o4"].contains(where: name.hasPrefix)
        case .deepseek: return name.hasPrefix("deepseek-")
        case .claude: return name.hasPrefix("claude-")
        default: return false
        }
    }

    static func ordered(_ models: [String], provider: AIProvider) -> [String] {
        func rank(_ name: String) -> Int {
            var score = 0
            if name.contains("flash") || name.contains("-mini") || name.contains("haiku") || name == "deepseek-chat" { score += 10 }
            if name.contains("preview") || name.contains("experimental") || name.contains("-exp") { score -= 20 }
            return score
        }
        return Array(Set(models)).sorted {
            if rank($0) != rank($1) { return rank($0) > rank($1) }
            return $0.compare($1, options: .numeric) == .orderedDescending
        }
    }

    static func request(url: URL, provider: AIProvider, key: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .gemini { request.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        else if provider == .claude {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    static func json(_ request: URLRequest, provider: AIProvider, session: URLSession) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200...299).contains(code) else {
            let error = object["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Không thể gọi API."
            throw NSError(domain: provider.rawValue, code: code, userInfo: [NSLocalizedDescriptionKey: "\(provider.shortName) (HTTP \(code)): \(message)"])
        }
        return object
    }

    static func models(provider: AIProvider, key: String, session: URLSession = .shared) async throws -> [String] {
        let endpoint: String
        switch provider {
        case .gemini: endpoint = "https://generativelanguage.googleapis.com/v1beta/models"
        case .openai: endpoint = "https://api.openai.com/v1/models"
        case .deepseek: endpoint = "https://api.deepseek.com/models"
        case .claude: endpoint = "https://api.anthropic.com/v1/models"
        default: return provider.defaultModels
        }
        var token: String? = nil
        var result: [String] = []
        var seen = Set<String>()
        repeat {
            var url = URLComponents(string: endpoint)!
            if provider == .gemini {
                url.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                if let token { url.queryItems?.append(URLQueryItem(name: "pageToken", value: token)) }
            } else if provider == .claude {
                url.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                if let token { url.queryItems?.append(URLQueryItem(name: "after_id", value: token)) }
            }
            let data = try await json(request(url: url.url!, provider: provider, key: key), provider: provider, session: session)
            let items = data[provider == .gemini ? "models" : "data"] as? [[String: Any]] ?? []
            for item in items {
                if provider == .gemini, !(item["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") { continue }
                let id = (item[provider == .gemini ? "name" : "id"] as? String ?? "").replacingOccurrences(of: "models/", with: "")
                if supportsText(id, provider: provider) { result.append(id) }
            }
            token = provider == .gemini ? data["nextPageToken"] as? String : ((data["has_more"] as? Bool == true) ? data["last_id"] as? String : nil)
            if let next = token, !seen.insert(next).inserted { token = nil }
        } while token != nil
        guard !result.isEmpty else { throw NSError(domain: provider.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Không có model văn bản tương thích với API key này."]) }
        return ordered(result, provider: provider)
    }

    static func completionRequest(prompt: String, provider: AIProvider, model: String, key: String) throws -> URLRequest {
        let endpoint: String
        var body: [String: Any]
        switch provider {
        case .gemini:
            guard model.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw URLError(.badURL) }
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            body = ["contents": [["role": "user", "parts": [["text": prompt]]]], "generationConfig": ["maxOutputTokens": 8192]]
        case .openai:
            // GPT-5+, GPT-6 and reasoning families use Responses; chat aliases and GPT-4 use Chat Completions.
            if model.hasPrefix("gpt-4") || model.contains("chat-latest") || model.hasPrefix("gpt-3.5") {
                endpoint = "https://api.openai.com/v1/chat/completions"
                body = ["model": model, "messages": [["role": "user", "content": prompt]], "max_completion_tokens": 8192, "store": false]
            } else {
                endpoint = "https://api.openai.com/v1/responses"
                body = ["model": model, "input": prompt, "max_output_tokens": 8192, "store": false]
            }
        case .deepseek:
            endpoint = "https://api.deepseek.com/chat/completions"
            body = ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": 8192]
        case .claude:
            endpoint = "https://api.anthropic.com/v1/messages"
            body = ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": 4096]
        default: throw URLError(.unsupportedURL)
        }
        var req = request(url: URL(string: endpoint)!, provider: provider, key: key)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func output(_ data: [String: Any], provider: AIProvider) throws -> String {
        var text = ""
        switch provider {
        case .gemini:
            let candidates = data["candidates"] as? [[String: Any]] ?? []
            let content = candidates.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        case .claude:
            text = (data["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .openai where data["output"] != nil:
            let output = data["output"] as? [[String: Any]] ?? []
            text = output.filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined()
        default:
            let choices = data["choices"] as? [[String: Any]] ?? []
            text = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NSError(domain: provider.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "\(provider.shortName) không trả về văn bản. Nội dung có thể bị chặn hoặc model đã dùng hết giới hạn suy luận."]) }
        return text
    }

    static func complete(prompt: String, provider: AIProvider, model: String, key: String, session: URLSession = .shared, timeout: TimeInterval = 60) async throws -> String {
        let budget = min(120, max(1, timeout))
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await completeWithinBudget(prompt: prompt, provider: provider, model: model, key: key, session: session) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private static func completeWithinBudget(prompt: String, provider: AIProvider, model: String, key: String, session: URLSession) async throws -> String {
        let selected = model.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "models/", with: "")
        func execute(_ id: String) async throws -> String {
            let req = try completionRequest(prompt: prompt, provider: provider, model: id, key: key)
            return try output(await json(req, provider: provider, session: session), provider: provider)
        }
        let resolved = await resolvedModel(provider: provider, model: selected, key: key)
        do { return try await execute(resolved.isEmpty ? provider.defaultModel : resolved) }
        catch {
            // Authentication, quota, server and network errors must not trigger paid retries on other models.
            guard (error as NSError).code == 404 else { throw error }
            let available = try await models(provider: provider, key: key, session: session)
            var lastError: Error = error
            for candidate in available.filter({ $0 != selected && $0 != resolved }).prefix(3) {
                do {
                    let result = try await execute(candidate)
                    await AIModelResolution.shared.set(provider.rawValue + "|" + selected + "|" + key, model: candidate)
                    NotificationCenter.default.post(name: modelResolved, object: nil, userInfo: ["provider": provider.rawValue, "previous": selected, "model": candidate])
                    return result
                }
                catch {
                    lastError = error
                    if (error as NSError).code != 404 { throw error }
                }
            }
            throw lastError
        }
    }
}
