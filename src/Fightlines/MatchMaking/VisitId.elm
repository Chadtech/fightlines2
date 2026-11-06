module Fightlines.MatchMaking.VisitId exposing
    ( VisitId
    , generator
    )

import Random



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


{-| Identifies one frontend page visit so responses from earlier visits can be ignored.
-}
type VisitId
    = VisitId Int



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


generator : Random.Generator VisitId
generator =
    Random.map VisitId (Random.int 0 Random.maxInt)
