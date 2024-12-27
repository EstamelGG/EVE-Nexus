extension EVECharacterInfo: Equatable {
    static func == (lhs: EVECharacterInfo, rhs: EVECharacterInfo) -> Bool {
        return lhs.CharacterID == rhs.CharacterID
    }
} 