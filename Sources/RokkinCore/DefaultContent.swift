import Foundation

public enum DefaultContent {
    /// Implementation intentions (Gollwitzer): "If situation X, then I do Y."
    public static let ifThenPlans: [String] = [
        "調べたくなったら → ⌃⌥M で駐車場にメモして、すぐ画面に戻る",
        "スマホに手が伸びたら → 置き場所に戻して、HUDのタスク名を声に出して読む",
        "Claudeの待ち時間になったら → 観察プロンプトに答える（何してる？期待どおり？）",
    ]

    /// Rotated while Claude Code is running. Turns passive watching (a slow "event rate",
    /// where ADHD performance is known to dip) into active verification.
    public static let observationPrompts: [String] = [
        "Claudeは今どの手順をやってる？ 一言で言うと？",
        "この画面、期待どおりの表示になってる？",
        "今の操作、QAケースの手順と一致してる？",
        "次にClaudeが何をするか予想してみよう",
        "文言・余白・状態表示で気になる所はある？ → ⌃⌥M でメモ",
        "エラー表示やコンソールの警告は出てない？",
        "使っているテストデータは正しい？",
        "ユーザーならここで迷わない？",
    ]

    public static let distractionTags: [String] = [
        "スマホ", "調べ物", "SNS・ニュース", "ぼーっと", "別の作業", "その他",
    ]

    /// An if-then plan aimed at the most frequent drift reason, offered on the dashboard.
    public static func suggestedPlan(for tag: String) -> String? {
        let plans: [String: String] = [
            "スマホ": "スマホに手が伸びたら → 置き場所に戻して、小窓のタスク名を声に出して読む",
            "調べ物": "調べたくなったら → ⌃⌥M でメモして、すぐ画面に戻る",
            "SNS・ニュース": "SNSやニュースを見たくなったら → ⌃⌥M に書いて、休憩まで取っておく",
            "ぼーっと": "手が止まったら → 次の1手だけを声に出して決める",
            "別の作業": "別の作業を思い出したら → ⌃⌥M にメモして、今の作業に戻る",
        ]
        return plans[tag]
    }

    public static let breakActivities: [String] = [
        "立って肩・背中を伸ばす（30秒）",
        "水を飲む",
        "窓の外や遠くを20秒見る",
        "その場で少し歩く／階段を往復",
    ]

    public static let distractingApps: [String] = [
        "メッセージ", "Messages", "LINE", "Discord", "ミュージック", "Music", "TV", "Podcasts",
    ]

    public static let distractingDomains: [String] = [
        "x.com", "twitter.com", "youtube.com", "instagram.com", "facebook.com",
        "tiktok.com", "reddit.com", "news.yahoo.co.jp", "b.hatena.ne.jp", "nicovideo.jp",
    ]
}
