module Game.UnitLoss exposing
    ( Details
    , DetailsError(..)
    , resolve
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Game.TurnPlayback as TurnPlayback exposing (Loss, LossCause)
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.UnitLoss.Cause as Cause exposing (Cause, NamedUnit)


type alias Details =
    { ownerName : String
    , cause : Cause
    }


type DetailsError
    = OwnerNotFound { unitId : UnitId, playerNumber : PlayerNumber }


{-| Resolve every owner required by a loss notice from the page's roster lookup.
Names stay separate from playback, which carries projected units and loss events.
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
                |> Result.map (NamedUnit attacker >> Cause.Destroyed kind)

        TurnPlayback.SuppliesExhausted ->
            Ok Cause.SuppliesExhausted

        TurnPlayback.ConcealedIndirectFire ->
            Ok Cause.ConcealedIndirectFire

        TurnPlayback.CarrierLost carrier carrierCause ->
            Result.map2 Cause.CarrierLost
                (resolveOwner ownerName carrier |> Result.map (NamedUnit carrier))
                (resolveCause ownerName carrierCause)
