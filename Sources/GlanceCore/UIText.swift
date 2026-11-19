import Foundation

/// Every user-facing string, in Turkish.
public enum UIText {
    private static let trigger = HotKeySpec.trigger.label
    private static let toggle = HotKeySpec.toggle.label

    public static let noResponseYet = "Henüz yanıt yok.\n\(trigger) ile ekranı yakalayıp sorun."
    /// Shown only if the user calls up the HUD before the answer has started.
    public static let waiting = "…"
    public static let emptyAnswer = "(Boş yanıt geldi.)"
    public static let truncatedNote = "… (yanıt uzunluk sınırında kesildi)"
    public static let incomplete = "Bağlantı, yanıt bitmeden kesildi. Yeniden deneyin."

    public static let footerIdle = "\(trigger) sor · \(toggle) göster/gizle"
    public static let footerFailed = "Hata · \(trigger) ile yeniden deneyin"
    public static let footerNotice = "GlanceHUD · \(toggle) gizle"
    public static func footerWaiting(model: String) -> String { "\(model) · bekleniyor" }
    public static func footerStreaming(model: String) -> String { "\(model) · yazıyor…" }
    public static func footerDone(model: String) -> String { "\(model) · \(toggle) gizle/göster" }

    public static let ready = "GlanceHUD hazır.\n\(trigger): ekranı yakala ve sor\n\(toggle): göster / gizle"
    public static let menuTrigger = "Ekranı yakala ve sor   \(trigger)"
    public static let menuToggle = "HUD'u göster / gizle   \(toggle)"
    public static let menuCalibrate = "Yakalama bölgesini seç…"
    public static let menuFullScreen = "Tüm ekranı yakala"

    public static let regionSaved = "Yakalama bölgesi kaydedildi. Bir sonraki \(trigger) yalnızca bu bölgeyi gönderir."
    public static let regionCleared = "Artık ekranın tamamı yakalanıyor."
    public static let regionFailed = "Bölge kaydedilemedi."

    public static let missingAPIKey = """
        API anahtarı bulunamadı. Anahtar Zinciri'ne eklemek için Terminal'de:
        security add-generic-password -s GlanceHUD -a anthropic-api-key -w
        (ya da ayar dosyasına "apiKey" alanını yazın)
        """

    public static let screenPermissionDenied = """
        Ekran kaydı izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > \
        Ekran ve Sistem Ses Kaydı bölümünden GlanceHUD'a izin verin, sonra uygulamayı yeniden açın.
        """

    public static func refused(category: String?) -> String {
        let detail = category.map { " (kategori: \($0))" } ?? ""
        return "Claude bu isteği yanıtlamadı; güvenlik denetimi takıldı\(detail). Farklı bir ekranla ya da istemle deneyin."
    }

    public static let configWarningShort = "Ayar dosyası hatalı"

    public static func configUnreadable(path: String) -> String {
        "Ayar dosyası okunamadı, varsayılanlar kullanılıyor:\n\(path)"
    }

    public static func hotKeyFailed(label: String, status: Int32) -> String {
        "\(label) kısayolu kaydedilemedi (hata \(status)). Başka bir uygulama kullanıyor olabilir."
    }

    public static func shortcutConflict(label: String) -> String {
        "\(label) bir macOS sistem kısayoluyla çakışıyor. Sistem Ayarları > Klavye > Klavye Kısayolları bölümünden kapatın."
    }
}
