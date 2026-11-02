module Fightlines.View.PrivacyPolicy exposing
    ( dialog
    , htmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)
import View.Prose as Prose



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


policy : String
policy =
    """I retain a log of every game, including the chat messages. I use this for debugging, when there are errors
and also so that I can understand people's user experience better and improve the game. I don't record any
other info right now"""



----------------------------------------------------------------
-- API --
----------------------------------------------------------------


htmlId : String
htmlId =
    "privacy-policy-dialog"



----------------------------------------------------------------
-- VIEW --
----------------------------------------------------------------


dialog : { onClose : msg } -> Dialog msg
dialog events =
    Dialog.make htmlId
        "privacy policy"
        events.onClose
        [ H.div
            [ A.css
                [ S.col
                , S.g4
                ]
            ]
            [ sectionView ]
        , Button.secondary "close" events.onClose
            |> Button.toHtml
        ]
        |> Dialog.reference
        |> Dialog.withCloseButton


sectionView : Html msg
sectionView =
    H.section
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        (Prose.paragraphs policy)
