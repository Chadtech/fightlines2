module Fightlines.View.Matchup exposing
    ( Side(..)
    , headerName
    , opening
    )

import Api.Enum.PlayerNumber as PlayerNumber
import Css
import Css.Media
import Game.BattlefieldSnapshot
    exposing
        ( Player
        )
import Game.Matchup
    exposing
        ( Matchup
        )
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S


type Side
    = Yours
    | Opposing


headerName : Bool -> Side -> Player -> Html msg
headerName mobile side player =
    H.div
        [ A.css
            [ S.minW0
            , Css.Media.withMediaQuery
                [ "(max-width: 659px)" ]
                [ S.when mobile [ S.displayNone ] ]
            ]
        ]
        [ playerName True side player ]


opening : Matchup -> Html msg
opening matchup =
    H.div
        [ A.css
            [ S.row
            , S.justifyCenter
            , S.itemsCenter
            , S.g3
            , S.textGray5
            ]
        ]
        [ playerName False Yours matchup.you
        , H.span [] [ H.text "vs" ]
        , playerName False Opposing matchup.opponent
        ]


playerName : Bool -> Side -> Player -> Html msg
playerName compact side player =
    let
        color : Css.Style
        color =
            case player.playerNumber of
                PlayerNumber.Player1 ->
                    S.bgRed1

                PlayerNumber.Player2 ->
                    S.bgBlue1

        direction : Css.Style
        direction =
            case side of
                Yours ->
                    S.row

                Opposing ->
                    Css.flexDirection Css.rowReverse

        nameOverflow : Css.Style
        nameOverflow =
            if compact then
                S.textEllipsis

            else
                S.wrapAnywhere
    in
    H.span
        [ A.title player.name
        , A.css
            [ S.row
            , direction
            , S.itemsCenter
            , S.justifyCenter
            , S.minW0
            , S.g2
            ]
        ]
        [ H.span
            [ A.css
                [ color
                , S.shrink0
                , S.w2p5
                , S.h2p5
                , S.border
                , S.borderGray4
                ]
            ]
            []
        , H.span
            [ A.css
                [ S.minW0
                , nameOverflow
                ]
            ]
            [ H.text player.name ]
        ]
