module Game.BackdropCalibration exposing
    ( Calibration
    , CopyScope(..)
    , Entry
    , Key
    , catalogSelection
    , copy
    , find
    , replace
    , save
    , suggested
    )

import Api.Enum.UnitKind exposing (UnitKind)
import Api.InputObject
import Api.Mutation
import Api.Object
import Api.Object.BackdropCalibration as CalibrationApi
import Api.Object.CalibratedBackdrop as BackdropApi
import Api.Query
import ApiRequest
import Graphql.Http
import Graphql.Operation exposing (RootQuery)
import Graphql.OptionalArgument as OptionalArgument
import Graphql.SelectionSet as SS exposing (SelectionSet)


{-| Percentages of the scene: footing is measured from the top, spacing is
vertical separation, unit size is the front vehicle width, rear scale is relative.
Each trench has its own bottom footing and width as percentages of the scene.
The second trench is ahead of the first in the direction the infantry face.
-}
type alias Calibration =
    { frontFooting : Float
    , rowSpacing : Float
    , unitSize : Float
    , rearScale : Float
    , trenchFooting : Float
    , trenchSize : Float
    , secondTrenchFooting : Float
    , secondTrenchSize : Float
    }


type alias Entry =
    { backdrop : String
    , unitKind : UnitKind
    , calibration : Calibration
    }


type CopyScope
    = OneUnit UnitKind
    | AllUnits


type alias Key =
    { backdrop : String
    , unitKind : UnitKind
    }


suggested : Calibration
suggested =
    { frontFooting = 94
    , rowSpacing = 9
    , unitSize = 25
    , rearScale = 78
    , trenchFooting = 86
    , trenchSize = 35
    , secondTrenchFooting = 86
    , secondTrenchSize = 35
    }


find : Key -> List Entry -> Maybe Calibration
find key catalog =
    catalog
        |> List.filter (matches key)
        |> List.head
        |> Maybe.map .calibration


replace : Entry -> List Entry -> List Entry
replace entry catalog =
    let
        key : Key
        key =
            { backdrop = entry.backdrop
            , unitKind = entry.unitKind
            }
    in
    entry :: List.filter (not << matches key) catalog


matches : Key -> Entry -> Bool
matches key entry =
    (entry.backdrop == key.backdrop) && (entry.unitKind == key.unitKind)


selection : SelectionSet Entry Api.Object.CalibratedBackdrop
selection =
    SS.succeed Entry
        |> SS.with BackdropApi.backdrop
        |> SS.with BackdropApi.unitKind
        |> SS.with
            (BackdropApi.calibration
                (SS.succeed Calibration
                    |> SS.with CalibrationApi.frontFooting
                    |> SS.with CalibrationApi.rowSpacing
                    |> SS.with CalibrationApi.unitSize
                    |> SS.with CalibrationApi.rearScale
                    |> SS.with CalibrationApi.trenchFooting
                    |> SS.with CalibrationApi.trenchSize
                    |> SS.with CalibrationApi.secondTrenchFooting
                    |> SS.with CalibrationApi.secondTrenchSize
                )
            )


catalogSelection : SelectionSet (List Entry) RootQuery
catalogSelection =
    Api.Query.backdropCalibrations selection


save : Entry -> Graphql.Http.Request Entry
save entry =
    Api.Mutation.saveBackdropCalibration
        { backdrop = entry.backdrop
        , unitKind = entry.unitKind
        , calibration = Api.InputObject.buildBackdropCalibrationInput entry.calibration
        }
        selection
        |> ApiRequest.mutationRequest


copy :
    { source : String
    , destination : String
    , scope : CopyScope
    }
    -> Graphql.Http.Request (List Entry)
copy request =
    let
        unitKind : OptionalArgument.OptionalArgument UnitKind
        unitKind =
            case request.scope of
                OneUnit kind ->
                    OptionalArgument.Present kind

                AllUnits ->
                    OptionalArgument.Absent
    in
    Api.Mutation.copyBackdropCalibrations
        (\options -> { options | unitKind = unitKind })
        { sourceBackdrop = request.source
        , destinationBackdrop = request.destination
        }
        selection
        |> ApiRequest.mutationRequest
