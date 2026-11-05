module Game.Assets exposing
    ( combatImagePaths
    , imagePaths
    )

import Api.Enum.BuildingKind as BuildingKind
import Api.Enum.MapTheme exposing (MapTheme)
import Api.Enum.ResourceKind as ResourceKind
import Game.Depot as Depot
import Game.Supply as Supply
import Game.UnitOrder as Order
import Game.View.CombatAttack as CombatAttack
import Game.View.CombatBazooka as CombatBazooka
import Game.View.CombatExplosion as CombatExplosion
import Game.View.CombatFormation as CombatFormation
import Game.View.CombatInfantry as CombatInfantry
import Game.View.CombatTheater as CombatTheater
import Game.View.TargetSight as TargetSight
import Game.View.TerrainTile as TerrainTile
import Game.View.UnitDeath as UnitDeath
import Game.View.UnitFacing as UnitFacing
import Game.View.UnitSprite as UnitSprite


{-| The download queue preserves this order: battlefield essentials before
combat presentation. Both factions are included regardless of current visibility.
Paths stay owned by the renderers, so preloading follows artwork changes.
-}
imagePaths : MapTheme -> List String
imagePaths theme =
    TerrainTile.imagePaths theme
        ++ UnitSprite.imagePaths
        ++ List.map Depot.kindImage [ BuildingKind.Supply, BuildingKind.Fuel, BuildingKind.Fortress ]
        ++ [ Depot.destroyedImage
           , Supply.cargoImage ResourceKind.Supply
           , Supply.cargoImage ResourceKind.Fuel
           , UnitDeath.imagePath
           , UnitFacing.imagePath
           , TargetSight.imagePath
           ]
        ++ List.map Order.image Order.all
        ++ combatImagePaths
        ++ CombatTheater.imagePaths theme


combatImagePaths : List String
combatImagePaths =
    CombatExplosion.imagePaths
        ++ CombatAttack.imagePaths
        ++ CombatBazooka.imagePaths
        ++ CombatInfantry.imagePaths
        ++ CombatFormation.imagePaths
