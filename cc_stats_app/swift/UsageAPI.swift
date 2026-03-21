import Foundation

/// Fetches Claude rate limit usage from Anthropic OAuth API.
/// Token is user-provided via Settings, stored in UserDefaults.
enum UsageAPI {

    static let tokenKey = "cc_stats_api_token"

    struct UsageData {
        let fiveHourPercent: Int       // 0-100
        let fiveHourResetsAt: Date?
        let sevenDayPercent: Int       // 0-100
        let sevenDayResetsAt: Date?
    }

    /// Fetch current rate limit usage. Returns nil if no token or request fails.
    static func fetch(completion: @escaping (UsageData?) -> Void) {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              !token.isEmpty else {
            completion(nil)
            return
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("cc-statistics/\(SettingsView.appVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }

            let fiveHour = json["five_hour"] as? [String: Any]
            let sevenDay = json["seven_day"] as? [String: Any]

            let result = UsageData(
                fiveHourPercent: fiveHour?["utilization"] as? Int ?? 0,
                fiveHourResetsAt: parseISO8601(fiveHour?["resets_at"] as? String),
                sevenDayPercent: sevenDay?["utilization"] as? Int ?? 0,
                sevenDayResetsAt: parseISO8601(sevenDay?["resets_at"] as? String)
            )
            completion(result)
        }.resume()
    }

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func formatResetTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "now" }
        let hours = Int(diff / 3600)
        let minutes = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }
}
