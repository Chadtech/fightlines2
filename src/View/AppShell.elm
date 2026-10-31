module View.AppShell exposing (toHtml)

import Css.Global
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatBazooka as CombatBazooka
import Game.View.CombatEffects as CombatEffects
import Game.View.CombatExplosion as CombatExplosion
import Game.View.CombatInfantry as CombatInfantry
import Game.View.CombatTheater as CombatTheater
import Game.View.DepotStock as DepotStock
import Game.View.TargetSight as TargetSight
import Game.View.TerrainTile as TerrainTile
import Game.View.UnitCargo as UnitCargo
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitFacing as UnitFacing
import Game.View.UnitWarnings as UnitWarnings
import Html.Styled as H exposing (Html)
import Html.Styled.Attributes as A
import Style as S
import View.Button as Button
import View.LoadingBar as LoadingBar


toHtml : List (Html msg) -> List (Html msg)
toHtml content =
    let
        globalStyles : Html msg
        globalStyles =
            Css.Global.global S.global

        shellContent : List (Html msg)
        shellContent =
            [ globalStyles
            , LoadingBar.styles
            , TargetSight.styles
            , TerrainTile.styles
            , TerrainTile.definitions
            , UnitFacing.styles
            , UnitCargo.styles
            , UnitWarnings.styles
            , CombatExplosion.styles
            , CombatExplosion.preload
            , CombatAttack.preload
            , CombatBazooka.preload
            , CombatInfantry.preload
            , UnitDeath.styles
            , CombatTheater.styles
            , CombatEffects.styles
            , DepotStock.styles
            , Button.styles
            ]
                ++ content
    in
    [ H.main_
        [ A.class TerrainTile.clockClass
        , A.css
            [ S.bgNightwood2
            , S.minHFullViewport
            , S.p4
            , S.textGray4
            , S.col
            , S.g3
            ]
        ]
        shellContent
    ]
