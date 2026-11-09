//
//  CallSummaryService.swift
//  WebRTCDialer
//
//  REST client for POST /api/calls/:callId/summary. The backend only accepts
//  calls it saw both parties agree to transcribe, sends the transcript to
//  Claude, and returns a summary; it does not keep the transcript.
//

import Foundation

enum CallSummaryService {

    enum SummaryError: LocalizedError {
        case notAuthenticated
        case server(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to generate summaries"
            case .server(let message): return message
            case .badResponse: return "Unexpected response from the server"
            }
        }
    }

    private struct RequestBody: Encodable {
        struct Line: Encodable {
            let speaker: String
            let text: String
            let startedAt: Date
        }
        let transcript: [Line]
    }

    private struct ResponseBody: Decodable {
        struct Summary: Decodable {
            let summary: String
            let actionItems: [String]?
            let keyPoints: [String]?
        }
        let success: Bool
        let summary: Summary?
        let error: String?
    }

    static func summarize(callId: String, transcript: [TranscriptLine]) async throws -> CallSummary {
        guard let token = AuthenticationService.shared.authToken else { throw SummaryError.notAuthenticated }
        let path = callId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? callId
        guard let url = URL(string: "\(Constants.API.baseURL)/api/calls/\(path)/summary") else { throw SummaryError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = transcript
            .filter { $0.isFinal || !$0.text.isEmpty }
            .map { RequestBody.Line(speaker: $0.speaker.rawValue, text: $0.text, startedAt: $0.startedAt) }
        request.httpBody = try encoder.encode(RequestBody(transcript: lines))

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SummaryError.server(decoded?.error ?? "Summary failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        guard let summary = decoded?.summary else { throw SummaryError.badResponse }
        return CallSummary(
            summary: summary.summary,
            actionItems: summary.actionItems ?? [],
            keyPoints: summary.keyPoints ?? [],
            generatedAt: Date()
        )
    }
}
