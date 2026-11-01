module Fightlines.View.PrivacyPolicy exposing
    ( Section(..)
    , all
    , dialog
    , htmlId
    )

import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Button as Button
import View.Dialog as Dialog exposing (Dialog)



----------------------------------------------------------------
-- TYPES --
----------------------------------------------------------------


type Section
    = Overview
    | InformationCollected
    | Storage
    | Contact



----------------------------------------------------------------
-- HELPERS --
----------------------------------------------------------------


all : List Section
all =
    [ Overview
    , InformationCollected
    , Storage
    , Contact
    ]


htmlId : String
htmlId =
    "privacy-policy-dialog"


sectionTitle : Section -> String
sectionTitle section =
    case section of
        Overview ->
            "overview"

        InformationCollected ->
            "information collected"

        Storage ->
            "storage and retention"

        Contact ->
            "contact"


{-| Fill in the policy here. Blank lines separate paragraphs.
-}
sectionText : Section -> String
sectionText section =
    case section of
        Overview ->
            ""

        InformationCollected ->
            ""

        Storage ->
            ""

        Contact ->
            ""



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
            (List.map sectionView all)
        , Button.secondary "close" events.onClose
            |> Button.toHtml
        ]
        |> Dialog.reference
        |> Dialog.withCloseButton


sectionView : Section -> Html msg
sectionView section =
    H.section
        [ A.css
            [ S.col
            , S.g2
            ]
        ]
        [ H.h2
            [ A.css
                [ S.textGray5
                ]
            ]
            [ H.text (sectionTitle section) ]
        , H.p
            [ A.css
                [ S.whitespacePreWrap
                , S.wrapAnywhere
                ]
            ]
            [ H.text (sectionText section) ]
        ]
