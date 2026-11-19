import Foundation

public enum GlanceError: Error, Equatable, Sendable {
    case missingAPIKey
    case screenPermissionDenied
    case captureFailed(String)
    case http(status: Int, type: String?, message: String?)
    case network(code: Int, description: String)
    case stream(type: String, message: String)

    /// Parses an API error body such as `{"type":"error","error":{"type":"...","message":"..."}}`.
    public static func fromHTTP(status: Int, body: Data) -> GlanceError {
        struct Envelope: Decodable {
            struct Inner: Decodable {
                let type: String?
                let message: String?
            }
            let error: Inner?
        }
        let inner = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        return .http(status: status, type: inner?.type, message: inner?.message)
    }

    /// Normalises transport errors; cancellations become `CancellationError` so callers can ignore them.
    public static func wrap(_ error: any Error) -> any Error {
        if error is CancellationError || error is GlanceError { return error }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            return GlanceError.network(code: urlError.code.rawValue, description: urlError.localizedDescription)
        }
        return GlanceError.network(code: 0, description: error.localizedDescription)
    }

    public var userMessage: String {
        switch self {
        case .missingAPIKey:
            return UIText.missingAPIKey
        case .screenPermissionDenied:
            return UIText.screenPermissionDenied
        case .captureFailed(let detail):
            return "Ekran yakalanamadı: \(detail)"
        case .http(let status, let type, let message):
            return Self.httpMessage(status: status, type: type, message: message)
        case .network(let code, let description):
            switch URLError.Code(rawValue: code) {
            case .notConnectedToInternet, .networkConnectionLost:
                return "İnternet bağlantısı yok ya da koptu."
            case .timedOut:
                return "İstek zaman aşımına uğradı. Yeniden deneyin."
            default:
                return "Bağlantı hatası: \(description)"
            }
        case .stream(let type, let message):
            if type == "overloaded_error" { return "Claude şu an çok yoğun. Biraz sonra yeniden deneyin." }
            return "Yanıt sırasında hata (\(type)): \(message)"
        }
    }

    private static func httpMessage(status: Int, type: String?, message: String?) -> String {
        let summary: String
        switch status {
        case 400: summary = "İstek kabul edilmedi (400)."
        case 401: summary = "API anahtarı geçersiz (401). Anahtarı kontrol edin."
        case 402: summary = "Hesapta ödeme sorunu var (402)."
        case 403: summary = "Bu anahtarın bu işleme izni yok (403)."
        case 404: summary = "Model bulunamadı (404). Ayar dosyasındaki \"model\" adını kontrol edin."
        case 413: summary = "İstek çok büyük (413). Ayar dosyasında \"maxImageLongEdge\" değerini düşürün."
        case 429: summary = "İstek sınırına takıldınız (429). Biraz bekleyip yeniden deneyin."
        case 529: summary = "Claude şu an çok yoğun (529). Biraz sonra yeniden deneyin."
        case 500...599: summary = "Sunucu hatası (\(status)). Biraz sonra yeniden deneyin."
        default: summary = "API hatası (\(status))."
        }
        guard let message, !message.isEmpty else { return summary }
        let detail = message.count > 240 ? String(message.prefix(240)) + "…" : message
        return "\(summary)\n\(type.map { "\($0): " } ?? "")\(detail)"
    }
}
