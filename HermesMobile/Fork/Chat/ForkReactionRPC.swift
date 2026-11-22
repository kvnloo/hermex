import Foundation

extension ForkRPC {
    static func messageReact(sessionID: String, rowID: Int, emoji: String?) -> ForkRPC {
        ForkRPC(
            method: "message.react",
            params: [
                "session_id": .string(sessionID),
                "row_id": .number(Double(rowID)),
                "emoji": emoji.map(BotJSON.string) ?? .null,
                "author": .string(ForkReaction.userAuthor),
            ],
            isAdmissible: !sessionID.isEmpty && rowID > 0
        )
    }
}

enum ForkReactionRows {
    static func parse(_ json: BotJSON) -> [ForkReaction] {
        (json.list ?? []).compactMap { ForkReaction(emoji: $0["emoji"].text, author: $0["author"].text) }
    }

    static func parse(_ json: JSONValue?) -> [ForkReaction] {
        guard case .array(let rows)? = json else { return [] }
        return rows.compactMap { row in
            guard case .object(let object) = row, case .string(let emoji)? = object["emoji"],
                  case .string(let author)? = object["author"] else { return nil }
            return ForkReaction(emoji: emoji, author: author)
        }
    }

    static func seeded(_ message: ChatMessage) -> [ForkReaction] {
        parse(message.displayMetadata?["reactions"])
    }

    static func displayMetadata(_ row: BotJSON) -> [String: JSONValue]? {
        var metadata = row["display_metadata"].argumentDictionary
        if case .array = row["reactions"], metadata?["reactions"] == nil {
            metadata = (metadata ?? [:]).merging(["reactions": row["reactions"].jsonValue]) { $1 }
        }
        return metadata
    }
}
