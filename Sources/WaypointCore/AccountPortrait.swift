import Foundation

/// Curated public Blizzard CDN assets. IDs are local preferences, not Battle.net avatar IDs.
public struct AccountPortrait: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let game: String
    public let url: URL

    public static let choices: [AccountPortrait] = {
        let wow = [("human_male", "Human"), ("orc_male", "Orc"),
                   ("nightelf_female", "Night Elf"), ("undead_male", "Undead")].map { key, name in
            AccountPortrait(id: "wow-\(key)", name: name, game: "World of Warcraft",
                url: URL(string: "https://blzmedia-a.akamaihd.net/wow/icons/56/achievement_character_\(key).jpg")!)
        }
        let diablo = [("barbarian_male", "Barbarian"), ("x1_crusader_male", "Crusader"),
                      ("demonhunter_female", "Demon Hunter"), ("monk_male", "Monk"),
                      ("p6_necro_male", "Necromancer"), ("witchdoctor_male", "Witch Doctor"),
                      ("wizard_female", "Wizard")].map { key, name in
            AccountPortrait(id: "d3-\(key)", name: name, game: "Diablo III",
                url: URL(string: "https://assets.diablo3.blizzard.com/d3/icons/portraits/64/\(key).png")!)
        }
        return wow + diablo
    }()
}
