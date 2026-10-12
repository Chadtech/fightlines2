module AppInitError exposing (view)

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Json.Decode as Decode
import Style as S
import View.Aria as Aria
import View.Card as Card
import View.CardHeader as CardHeader
import View.Textarea as Textarea


view : Decode.Error -> List (Html msg)
view error =
    [ H.div
        [ Aria.role Aria.Alert
        , A.css
            [ S.flex1
            , S.col
            , S.justifyCenter
            , S.g3
            ]
        ]
        [ Card.toHtml
            (Card.simple
                |> Card.withHeader (CardHeader.simple "app failed to initialize")
            )
            [ H.p
                [ A.css [ S.textRed1 ]
                ]
                [ H.text "fightlines could not start because its initialization data is invalid."
                ]
            , H.p
                []
                [ H.text "reload the page to try again. if this continues, report the error below."
                ]
            , H.label
                [ A.css
                    [ S.col
                    , S.g2
                    ]
                ]
                [ H.text "initialization error details"
                , H.div
                    [ A.css
                        [ S.h64
                        ]
                    ]
                    [ Textarea.readOnly (Decode.errorToString error)
                        |> Textarea.toHtml
                    ]
                ]
            ]
        ]
    ]
