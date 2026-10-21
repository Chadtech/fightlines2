module Game.UnitLoss.Cause exposing
    ( Cause(..)
    , NamedUnit
    )

import Api.Enum.CombatKind exposing (CombatKind)
import Game.Unit exposing (Unit)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Cause
    = Destroyed CombatKind NamedUnit
    | ConcealedIndirectFire
    | SuppliesExhausted
    | CarrierLost NamedUnit Cause


type alias NamedUnit =
    { unit : Unit
    , ownerName : String
    }
