module UnitLoss exposing
    ( Cause(..)
    , Details
    , DetailsError(..)
    , NamedUnit
    , resolve
    )

import Api.Enum.CombatKind exposing (CombatKind)
import Api.Enum.PlayerNumber exposing (PlayerNumber)
import TurnPlayback exposing (Loss, LossCause)
import Unit exposing (Unit)
import UnitId exposing (UnitId)


type alias Details =
    { ownerName : String
    , cause : Cause
    }


type DetailsError
    = OwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }


type alias NamedUnit =
    { unit : Unit
    , ownerName : String
    }


type Cause
    = Destroyed CombatKind NamedUnit
    | SuppliesExhausted
    | CarrierLost NamedUnit Cause


{-| Resolve every owner required by a loss notice from the page's roster lookup.
Names stay separate from playback, which only carries projected units and shots.
-}
resolve : (Unit -> Maybe String) -> Loss -> Result DetailsError Details
resolve ownerName loss =
    Result.map2 Details
        (resolveOwner ownerName loss.unit)
        (resolveCause ownerName loss.cause)


resolveOwner : (Unit -> Maybe String) -> Unit -> Result DetailsError String
resolveOwner ownerName unit =
    ownerName unit
        |> Result.fromMaybe (OwnerNotFound { unitId = unit.id, playerNumber = unit.playerNumber })


resolveCause : (Unit -> Maybe String) -> LossCause -> Result DetailsError Cause
resolveCause ownerName cause =
    case cause of
        TurnPlayback.Destroyed kind attacker ->
            resolveOwner ownerName attacker
                |> Result.map (NamedUnit attacker >> Destroyed kind)

        TurnPlayback.SuppliesExhausted ->
            Ok SuppliesExhausted

        TurnPlayback.CarrierLost carrier carrierCause ->
            Result.map2 CarrierLost
                (resolveOwner ownerName carrier |> Result.map (NamedUnit carrier))
                (resolveCause ownerName carrierCause)
