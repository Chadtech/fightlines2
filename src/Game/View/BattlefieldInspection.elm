module Game.View.BattlefieldInspection exposing
    ( cargo
    , toHtml
    , unloadingFreight
    )

import Api.Enum.PlayerNumber exposing (PlayerNumber)
import Css
import Game.Coordinate as Coordinate exposing (Coordinate)
import Game.Depot as Depot exposing (Depot)
import Game.Map as Map exposing (Map)
import Game.Supply as Supply
import Game.Unit as Unit exposing (Unit)
import Game.UnitId as UnitId exposing (UnitId)
import Game.View.Cargo as CargoView
import Game.View.DepotStatus as DepotStatus
import Game.View.InspectionHelp as InspectionHelp
import Game.View.SupplyCrate as SupplyCrate
import Game.View.TerrainInfo as TerrainInfo
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Html.Styled.Keyed as Keyed
import Style as S
import View.Aria as Aria
import View.Layout as Layout exposing (Layout)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type alias Contents msg =
    { onHelp : InspectionHelp.Help -> msg
    , map : Map
    , depots : List Depot
    , supplyCrates : List Supply.GroundCrate
    , visibleTiles : List Coordinate
    , position : Maybe Coordinate
    , unit : Maybe { unit : Unit, content : List (Html msg) }
    }


type alias CargoArgs msg =
    { units : List Unit
    , ownPlayers : List PlayerNumber
    , onSelectPassenger : UnitId -> msg
    , onHelp : InspectionHelp.Help -> msg
    }



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


toHtml : Layout -> Contents msg -> Html msg
toHtml layout model =
    let
        unitRows : List ( String, Html msg )
        unitRows =
            case model.unit of
                Just inspected ->
                    [ ( UnitId.toString inspected.unit.id
                      , inspectionRow (Unit.label inspected.unit) inspected.content
                      )
                    ]

                Nothing ->
                    []

        tileRows : List ( String, Html msg )
        tileRows =
            case model.position of
                Just coordinate ->
                    let
                        coordinateKey : String
                        coordinateKey =
                            String.fromInt coordinate.x ++ "," ++ String.fromInt coordinate.y

                        depotRows : List ( String, Html msg )
                        depotRows =
                            model.depots
                                |> List.filter (\depot -> depot.position == coordinate)
                                |> List.map depotRow

                        depotRow : Depot -> ( String, Html msg )
                        depotRow depot =
                            ( "depot:" ++ coordinateKey
                            , inspectionRow (Depot.label depot)
                                [ DepotStatus.toHtml
                                    model.onHelp
                                    layout
                                    depot
                                ]
                            )

                        crateRows : List ( String, Html msg )
                        crateRows =
                            model.supplyCrates
                                |> List.filter (\crate -> crate.position == coordinate)
                                |> List.indexedMap crateRow

                        crateRow : Int -> Supply.GroundCrate -> ( String, Html msg )
                        crateRow index crate =
                            ( "crate:" ++ coordinateKey ++ ":" ++ Supply.cargoLabel crate.stock.kind ++ ":" ++ String.fromInt index
                            , inspectionRow (Supply.cargoLabel crate.stock.kind)
                                [ SupplyCrate.toHtml { lastSeen = not (List.member coordinate model.visibleTiles) } crate.stock ]
                            )

                        terrainRows : List ( String, Html msg )
                        terrainRows =
                            [ ( "terrain:" ++ coordinateKey
                              , inspectionRow "terrain"
                                    [ terrainView layout model coordinate ]
                              )
                            ]
                    in
                    depotRows ++ crateRows ++ terrainRows

                Nothing ->
                    []

        rows : List ( String, Html msg )
        rows =
            unitRows ++ tileRows
    in
    inspectionView rows


unloadingFreight : Int -> Supply.CargoStock -> Html msg
unloadingFreight cargoIndex stock =
    inspectionView
        [ ( "unloading:" ++ String.fromInt cargoIndex
          , inspectionRow (Supply.cargoLabel stock.kind)
                [ SupplyCrate.toHtml { lastSeen = False } stock ]
          )
        ]


inspectionView : List ( String, Html msg ) -> Html msg
inspectionView rows =
    Keyed.node "section"
        [ Aria.label "selection"
        , A.css
            [ S.col
            , S.g3
            , S.shrink0
            ]
        ]
        rows


inspectionRow : String -> List (Html msg) -> Html msg
inspectionRow label contents =
    H.section
        [ Aria.label label
        , A.css
            [ S.col
            , S.g3
            , S.shrink0
            , Css.pseudoClass "not(:last-child)"
                [ S.borderB
                , S.borderGray2
                , S.pb2
                ]
            ]
        ]
        contents


terrainView : Layout -> Contents msg -> Coordinate -> Html msg
terrainView layout model coordinate =
    let
        content : Html msg
        content =
            case layout of
                Layout.Desktop ->
                    TerrainInfo.toHtml
                        { onHelp = model.onHelp }
                        model.map
                        coordinate

                Layout.Mobile ->
                    TerrainInfo.helpButton
                        { onHelp = model.onHelp }
                        model.map
                        coordinate
    in
    Keyed.node "div"
        []
        [ ( String.fromInt coordinate.x ++ "," ++ String.fromInt coordinate.y
          , content
          )
        ]


cargo : CargoArgs msg -> Unit -> Html msg
cargo args unit =
    let
        passengers : List Unit
        passengers =
            List.filter (\passenger -> Unit.carrierId passenger == Just unit.id) args.units

        freight : List Supply.CargoStock
        freight =
            unit.resources
                |> Maybe.map .supplyCargo
                |> Maybe.withDefault []

        canInspectCargo : Bool
        canInspectCargo =
            List.member unit.playerNumber args.ownPlayers && unit.cargoCapacity > 0
    in
    if canInspectCargo then
        CargoView.toHtml
            { capacity = unit.cargoCapacity
            , passengers = passengers
            , freight = freight
            , onSelectPassenger = args.onSelectPassenger
            , onHelp = args.onHelp
            }

    else
        H.text ""
