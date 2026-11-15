module Fightlines.GameOrigin exposing
    ( GameOrigin(..)
    , queryParser
    )

import Url.Parser.Query as Query



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type GameOrigin
    = DirectEntry
    | MatchMaking



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


gameOrigin : Maybe String -> GameOrigin
gameOrigin source =
    case source of
        Just "match-making" ->
            MatchMaking

        _ ->
            DirectEntry



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


queryParser : Query.Parser GameOrigin
queryParser =
    Query.map gameOrigin (Query.string "from")
