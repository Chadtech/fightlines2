module Game.BackdropCalibration exposing
    ( Calibration
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
import Graphql.SelectionSet as SS exposing (SelectionSet)


{-| Percentages of the scene: footing is measured from the top, spacing is
vertical separation, unit size is the front vehicle width, rear scale is relative.
Trench footing independently positions the bottom of the trench overlays;
trench size is each overlay’s width as a percentage of the scene.
-}
type alias Calibration =
    { frontFooting : Float
    , rowSpacing : Float
    , unitSize : Float
    , rearScale : Float
    , trenchFooting : Float
    , trenchSize : Float
    }


type alias Entry =
    { backdrop : String
    , unitKind : UnitKind
    , calibration : Calibration
    }


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
    }
    -> Graphql.Http.Request (List Entry)
copy request =
    Api.Mutation.copyBackdropCalibrations
        { sourceBackdrop = request.source
        , destinationBackdrop = request.destination
        }
        selection
        |> ApiRequest.mutationRequest
