module Game.ArmyStyle exposing
    ( ArmyStyle(..)
    , label
    , priority
    , slug
    )


type ArmyStyle
    = AmazonCorporate
    | ChaosCultist
    | CommunistChina
    | ImperialJapan
    | NaziGermany
    | UnitedStates


{-| The first enabled style wins. The Features tab lists styles in this order.
-}
priority : List ArmyStyle
priority =
    [ AmazonCorporate
    , ChaosCultist
    , CommunistChina
    , ImperialJapan
    , NaziGermany
    , UnitedStates
    ]


label : ArmyStyle -> String
label style =
    String.replace "-" " " (slug style)


slug : ArmyStyle -> String
slug style =
    case style of
        AmazonCorporate ->
            "amazon-corporate"

        ChaosCultist ->
            "chaos-cultist"

        CommunistChina ->
            "communist-china"

        ImperialJapan ->
            "imperial-japan"

        NaziGermany ->
            "nazi-germany"

        UnitedStates ->
            "united-states"
