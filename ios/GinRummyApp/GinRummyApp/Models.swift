import Foundation

struct PlayerPerspective: Codable, Equatable {
    let seat: Int
    let hands: [[String]]
    let stockCount: Int
    let discard: [String]
    let phase: String
    let dealer: Int
    let nonDealer: Int
    let currentTurn: Int
    let scores: [Int]
    let handsWon: [Int]
    let raceTarget: Int
    let upcardOffer: UpcardOfferState?
    let knock: KnockPerspective?
    /// First upcard for this hand (knock value); fixed for the whole hand. Not the current discard top.
    let knockCheckCard: String?
    /// After first hand cut, both cut cards; cleared next hand. Used for a short "who won" banner.
    let lastCut: LastCutResult?
    let cut: CutState?

    struct LastCutResult: Codable, Equatable {
        let p0: String
        let p1: String
        let nonDealer: Int
    }

    /// Face-down high-card cut: pick by index into the 52 card spread; no card codes shown until you cut.
    struct CutState: Codable, Equatable {
        let faceDownRemaining: Int
        let activePicker: Int
        let youMustPick: Bool
        let yourCut: String?
        let opponentHasPicked: Bool
        let theirCut: String?
        /// Server chooses who cuts first; omitted in older games (treated as 0).
        let firstCutSeat: Int?
    }

    struct UpcardOfferState: Codable, Equatable {
        let stage: String
        let nonDealerPassed: Bool
    }

    struct KnockPerspective: Codable, Equatable {
        let knocker: Int
        let knockCard: String
        let knockerMelds: [MeldDTO]
        let knockerDeadwood: [String]
        let opponentOriginalHand: [String]?
        let opponentDeadwood: [String]
        let knockerMeldsAfterLayoff: [MeldDTO]?
        let layoffTurn: Int

        struct MeldDTO: Codable, Equatable {
            let type: String
            let cards: [String]
        }
    }
}

struct LobbyCreateResponse: Codable {
    let lobby: LobbyDTO

    struct LobbyDTO: Codable {
        let id: String
        let invite_code: String
        let status: String
    }
}

struct LobbyStatusResponse: Codable {
    let lobby: LobbyDTO
    let gameId: String?

    struct LobbyDTO: Codable {
        let id: String
        let invite_code: String
        let status: String
    }
}

struct GameStartResponse: Codable {
    let gameId: String
    let perspective: PlayerPerspective
    let testBot: Bool?
}

struct BettingDTO: Codable {
    let raw: Int?
    let bucket: Int?
}

struct GameStateResponse: Codable {
    let perspective: PlayerPerspective
    let moveSeq: Int
    let status: String
    let betting: BettingDTO?
}

struct MoveResponse: Codable {
    let perspective: PlayerPerspective
    let moveSeq: Int
    let betting: BettingDTO?
}

struct AuthTokenResponse: Codable {
    let access_token: String
    /// Supabase rotates the refresh token on every refresh; persist whichever one we last received.
    let refresh_token: String?
    /// Seconds-until-expiry from the auth server. Combine with the local clock to compute `expiresAt`.
    let expires_in: Int?
    let token_type: String?
    let user: AuthUser?

    struct AuthUser: Codable {
        let id: String
        let email: String?
    }
}
