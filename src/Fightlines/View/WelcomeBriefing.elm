module Fightlines.View.WelcomeBriefing exposing
    ( dialog
    , dialogHtmlId
    , styles
    )

import Api.Enum.BuildingKind as BuildingKind
import Api.Enum.Entrenchment as Entrenchment
import Api.Enum.PlayerNumber as PlayerNumber
import Api.Enum.ResourceKind as ResourceKind
import Api.Enum.SpriteFacing as SpriteFacing
import Api.Enum.UnitKind as UnitKind exposing (UnitKind)
import Css
import Game.Depot as Depot
import Game.Supply as Supply
import Game.View.UnitSprite as UnitSprite
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import Svg.Styled as Svg
import Svg.Styled.Attributes as SA
import View.Aria as Aria
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type SupplySquare
    = OutsideRange
    | Supplied
    | Crate
    | Infantry



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


dialogHtmlId : String
dialogHtmlId =
    "welcome-briefing"


welcome : Html msg
welcome =
    H.h2
        [ A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.relative
            , S.isolate
            , S.overflowHidden
            , S.textYellow5
            , S.textAlignCenter
            , S.p4
            , S.after
                [ S.contentEmpty
                , S.absolute
                , S.inset0
                , S.pointerEventsNone
                , Css.property "background"
                    ("linear-gradient(110deg, transparent 35%, " ++ S.gray5Str ++ "2b 50%, transparent 65%)")
                , S.transform "translateX(-150%)"
                , S.animation "fightlines-welcome-glare 4.8s ease-in-out .2s infinite"
                , S.reducedMotion
                    [ S.animationNone
                    , S.displayNone
                    ]
                ]
            ]
        ]
        [ H.text "welcome to fightlines!"
        ]


image : String -> Html msg
image path =
    H.img
        [ A.src path
        , A.alt ""
        , A.css
            [ S.block
            , S.wFull
            , S.hFull
            , S.objectContain
            ]
        ]
        []


unitArtwork : UnitKind -> Html msg
unitArtwork kind =
    Svg.svg
        [ SA.viewBox "0 0 16 16"
        , SA.width "100%"
        , SA.height "100%"
        , Aria.hidden True
        ]
        [ UnitSprite.portraitToSvg
            { kind = kind
            , playerNumber = PlayerNumber.Player1
            , spriteFacing = SpriteFacing.Right
            , entrenchment = Entrenchment.Exposed
            }
        ]


frontLine : Html msg
frontLine =
    Svg.svg
        [ SA.viewBox "0 0 20 20"
        , SA.width "100%"
        , SA.height "100%"
        , Aria.hidden True
        ]
        [ UnitSprite.portraitToSvg
            { kind = UnitKind.Tank
            , playerNumber = PlayerNumber.Player1
            , spriteFacing = SpriteFacing.Right
            , entrenchment = Entrenchment.Exposed
            }
        , Svg.image
            [ SA.x "10"
            , SA.y "11"
            , SA.width "10"
            , SA.height "10"
            , SA.xlinkHref (Supply.cargoImage ResourceKind.Supply)
            ]
            []
        ]


flowStop : String -> Html msg -> Html msg
flowStop label artwork =
    H.div
        [ A.css
            [ S.col
            , S.itemsCenter
            , S.g2
            , S.minW0
            ]
        ]
        [ H.div
            [ A.css
                [ S.maxWFull
                , S.w24
                , S.h24
                , S.belowWidth 520
                    [ S.w16
                    , S.h16
                    ]
                ]
            ]
            [ artwork
            ]
        , H.span
            [ A.css
                [ S.textGray5
                , S.textAlignCenter
                ]
            ]
            [ H.text label
            ]
        ]


supplyLine : Html msg
supplyLine =
    let
        arrow : Html msg
        arrow =
            H.span
                [ Aria.hidden True
                , A.css
                    [ S.textAlignCenter
                    ]
                ]
                [ H.text "→"
                ]
    in
    H.div
        [ A.css
            [ S.bgNightwood3
            , S.indentStrong
            , S.p3
            , S.grid
            , S.gridColumns "minmax(0, 1fr) 1rem minmax(0, 1fr) 1rem minmax(0, 1fr)"
            , S.itemsCenter
            , S.g1
            , S.belowWidth 520
                [ S.p2
                , S.g0p5
                ]
            ]
        , Aria.role Aria.Image
        , Aria.label "supply line: load crates at a depot, carry them by truck, and unload near your units"
        ]
        [ flowStop "supply depot" (image (Depot.kindImage BuildingKind.Supply))
        , arrow
        , flowStop "loaded truck" (unitArtwork UnitKind.Truck)
        , arrow
        , flowStop "front line" frontLine
        ]


step : { number : String, title : String, description : String } -> Html msg
step details =
    H.section
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.h3
            [ A.css
                [ S.textGray5
                ]
            ]
            [ H.span
                [ A.css
                    [ S.textYellow5
                    ]
                ]
                [ H.text (details.number ++ ". ")
                ]
            , H.text details.title
            ]
        , H.p
            []
            [ H.text details.description
            ]
        ]


steps : Html msg
steps =
    H.div
        [ A.css
            [ S.grid
            , S.gridColumns "repeat(3, minmax(0, 1fr))"
            , S.g4
            , S.belowWidth 520
                [ S.gridCols1
                , S.g3
                ]
            ]
        ]
        [ step
            { number = "1"
            , title = "load up"
            , description = "move or hold a truck on a supply depot. choose crates to load."
            }
        , step
            { number = "2"
            , title = "bring supplies"
            , description = "park beside your units. crates aboard resupply them at turn end."
            }
        , step
            { number = "3"
            , title = "leave a supply point"
            , description = "unload a crate to keep supplying units after the truck leaves."
            }
        ]


supplySquare : SupplySquare -> Html msg
supplySquare square =
    let
        content : Html msg
        content =
            case square of
                Crate ->
                    image (Supply.cargoImage ResourceKind.Supply)

                Infantry ->
                    unitArtwork UnitKind.Infantry

                _ ->
                    H.text ""

        surface : List Css.Style
        surface =
            case square of
                OutsideRange ->
                    [ S.bgGray1
                    , S.borderGray2
                    ]

                Crate ->
                    [ S.bgNightwood3
                    , S.borderYellow5
                    ]

                _ ->
                    [ S.bgNightwood2
                    , S.borderGray4
                    ]
    in
    H.div
        [ A.css
            [ S.border
            , S.minW0
            , Css.batch surface
            ]
        ]
        [ content
        ]


resupplyRange : Html msg
resupplyRange =
    H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g4
            , S.borderT
            , S.borderB
            , S.borderGray2
            , S.py3
            ]
        ]
        [ H.div
            [ A.css
                [ S.grid
                , S.gridColumnsRem 3 1.5
                , S.gridRowsRem 3 1.5
                , S.g0p5
                , S.shrink0
                ]
            , Aria.role Aria.Image
            , Aria.label "supplies reach the source square and four side-adjacent squares, but not diagonals"
            ]
            (List.map supplySquare
                [ OutsideRange
                , Infantry
                , OutsideRange
                , Supplied
                , Crate
                , Supplied
                , OutsideRange
                , Supplied
                , OutsideRange
                ]
            )
        , H.div
            [ A.css
                [ S.col
                , S.g2
                , S.minW0
                ]
            ]
            [ H.p
                [ A.css
                    [ S.textGray5
                    ]
                ]
                [ H.text "same square or one square beside it."
                ]
            , H.p
                []
                [ H.text "depots and crates resupply automatically at turn end, while stock lasts. diagonals do not count."
                ]
            ]
        ]


fuel : Html msg
fuel =
    H.div
        [ A.css
            [ S.row
            , S.itemsCenter
            , S.g3
            ]
        ]
        [ H.div
            [ A.css
                [ S.w12
                , S.h12
                , S.shrink0
                ]
            ]
            [ image (Supply.cargoImage ResourceKind.Fuel)
            ]
        , H.p
            []
            [ H.text "tanks and trucks also need fuel to move. collect fuel drums at fuel depots and deliver them the same way."
            ]
        ]


warning : Html msg
warning =
    H.p
        [ A.css
            [ S.row
            , S.itemsStart
            , S.g3
            , S.textGray5
            ]
        ]
        [ H.span
            [ A.css
                [ S.textYellow5
                , S.shrink0
                ]
            , Aria.hidden True
            ]
            [ H.text "⚠"
            ]
        , H.span
            []
            [ H.text "at zero supplies, units cannot fight. resupply within two turns or lose them."
            ]
        ]



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


dialog : { onClose : msg } -> Dialog msg
dialog events =
    Dialog.make dialogHtmlId
        "before your first turn"
        events.onClose
        [ H.div
            [ Aria.label "game basics"
            , A.tabindex 0
            , A.css
                [ S.minH0
                , S.overflowAuto
                , S.pr1
                ]
            ]
            [ H.div
                [ A.css
                    [ S.col
                    , S.g3
                    ]
                ]
                [ welcome
                , H.p
                    []
                    [ H.text "resupply is a core game mechanic. every unit uses supplies each turn, even while holding position. you can lose units if they are not properly supplied."
                    ]
                , H.p
                    []
                    [ H.text "give orders, then submit your turn. both armies act together."
                    ]
                , supplyLine
                , steps
                , resupplyRange
                , fuel
                , warning
                ]
            ]
        , H.div
            [ A.css
                [ S.shrink0
                , S.borderT
                , S.borderGray2
                , S.pt3
                ]
            ]
            [ Button.primary "got it — let's play" events.onClose
                |> Button.toHtml
            ]
        ]
        |> Dialog.article
        |> Dialog.withCloseButton


styles : Html msg
styles =
    H.node "style"
        []
        [ H.text """
            @keyframes fightlines-welcome-glare {
                0%, 35% { transform: translateX(-150%); }
                75%, 100% { transform: translateX(150%); }
            }
            """
        ]
