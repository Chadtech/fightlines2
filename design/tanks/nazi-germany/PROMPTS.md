# Recorded generation prompts

## v1 · 2026-11-12

Built-in ImageGen edit. [Concept v1](concept-v1.png) is a static 1254 × 1254 RGBA sprite.

- Image 1 is the [high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png).
- Image 2 is the [approved infantry concept](../../infantry/nazi-germany/concept-v9.png).

```text
Use case: precise-object-edit
Asset type: a single static FightLines strategy-game map sprite
Image 1 is the neutral tank to edit and the strict geometry, camera, and framing template. Image 2 is the approved faction infantry concept, for the muted olive-gray, field-gray, and charcoal palette and hand-painted anime finish only. Depict one fictional modern tracked tank.

Keep the exact near-side-on, slightly elevated, right-facing view of Image 1, with a horizontal barrel pointing right and the visible track run level. Match the unusually tall, chunky proportions. Preserve the broad track base, upper turret height, hull-to-turret balance, and approximate locations of the rear track edge, front track edge, muzzle, top of turret, and bottom of tracks. It should still read as an almost square vehicle on a small map tile. Keep the barrel visually compact and fully contained in the square, as in the source.

Redesign the armor surfaces in the visual lineage of a Panther-era Panzer, reinterpreted as a distinctly modern fictional vehicle. Use a strong slanted glacis, angular shoulders, and large interlocking, clearly differentiated armor planes that give the turret a faceted silhouette. Use modern segmented side skirts with substantial exposed tracks and dark road wheels below, discreet blocky optics, and a low angular hatch. Keep the main shapes clear and weighty. Use field-gray and desaturated green-gray armor, charcoal running gear, subtle cool optical glass, and restrained edge wear.

High-detail 1980s hand-drawn anime mechanical illustration. Use confident dark ink contours, crisply separated cel-shaded planes, painted edge highlights and subtle surface texture. Group shadows and highlights into large readable masses for a strategy map at small sizes. No emblems, flags, lettering, slogans, or insignia. No crew, action, effects, terrain, ground shadow, or backdrop.

Square canvas with real alpha transparency. Show the complete vehicle, including the muzzle and every part of the tracks. Match the reference's close crop with a thin clear margin at the sides and slightly more room above and below. The empty area around the entire silhouette must be fully transparent.
```

## v2 · 2026-11-12

Built-in ImageGen edit. [Concept v2](concept-v2.png) is a static 1254 × 1254 RGBA sprite.

The first edit used [concept v1](concept-v1.png) and established the turret and glacis.

```text
Use case: precise-object-edit
Asset type: one fictional modern tank sprite for the FightLines strategy map.
Edit image 1, FightLines tank concept v1. Use its camera, running gear and canvas coverage as the placement guide. Replace the entire drawn turret, barrel exterior and front half of the upper hull with new shapes. This is a silhouette redesign.

Give the turret a distinctive modern German arrowhead silhouette inspired by Leopard 2-style wedge cheeks and the angular massing of a Panther-era Panzer. From this right-facing side view, draw one continuous broad turret with a long squared rear bustle extending visibly to the left and a low, nearly flat roof. At the front, give it a bold projecting wedge cheek with a sharp point beside the gun and a prominent diagonal cutback underneath. Render the cheek as a large light upper plane and a deep shadowed lower plane so the arrowhead is obvious at 32 pixels. The rear bustle should form a clear left-hand overhang above the hull. Replace the old stacked cupola, paired face windows, and upright roof sensors with a flush hatch and one small recessed optical block. Replace the old thick ringed muzzle with a more slender, smooth-sided barrel silhouette with one subtle sleeve and a plain muzzle, still ending about where the original did.

Redraw the front hull as a single tall glacis facet that descends steeply and visibly from just forward of the turret down to a sharp nose on the right. Remove the front box and exposed orange lamp silhouette, and recess any lighting into the new armor. Use a clear diagonal exterior break and strong tonal separation at the nose, with a slanted front skirt plate tying it into the existing track run. Keep the rest of the track silhouette broad and level.

Preserve the near-side-on, slightly elevated camera, rightward horizontal barrel, big square-ish vehicle mass, the full tile-filling stance, and approximately the existing track bottom and width. The redesigned roof should still reach close to the original upper silhouette so the sprite stays substantial. Keep a visibly clear margin around all parts of the tank, including the muzzle, on a square canvas with genuine alpha transparency. Center it as a single isolated sprite. No ground, shadow, scenery, crew, symbols, lettering, flags, or insignia.

High-detail 1980s hand-painted anime mechanical illustration with strong ink contours and painted cel shading. Muted field-gray and green-gray armor, charcoal tracks, subdued cool optical glass, and light edge wear. Favor broad, visually legible armor planes.
```

The second edit used the first pass as image 1 and concept v1 as image 2. It restored the tank's vertical footprint and sharpened the slope of the front armor.

```text
Use case: precise-object-edit
Asset type: one transparent square sprite of a fictional modern tank for the FightLines strategy map.
Edit image 1, the first v2 draft with the German-inspired wedge turret. Image 2 is concept v1, a height and canvas-framing reference only.

The main edit is to make the new continuous wedge turret substantially taller so it fills the tile vertically again. Keep the tracks and hull base in the same place on the canvas. Raise the turret roof and hatch into the large transparent area above it, from the current one-quarter of the canvas to approximately one-eighth of the canvas measured from the top. Add that height through the solid main armor body of the turret. Keep the long overhanging bustle to the left, nearly flat roof, low flush hatch, single recessed optical block, and sharp forward-projecting arrowhead cheek. Draw a much deeper wedge cheek with a broad light upper plane, dark diagonal cutback underneath, and its point just beside the barrel base. Keep the current slender right-facing horizontal barrel with a plain muzzle. Keep a continuous modern turret shell. The reference v1's stacked cupola, roof sensor pods, boxy turret face, and ringed muzzle should stay absent. The thicker, tall angular silhouette must be visible at 32px.

Give the hull nose a steeper visual profile by shortening the horizontal run of the prominent sloping front armor face. Keep the pointed right nose and the track footprint in place. Preserve image 1's near-side-on slightly elevated camera, field-gray palette, heavy ink contours, and detailed hand-painted 1980s anime cel shading. Same square framing and scale, with real alpha transparency and a little clean clearance around the entire silhouette, including the muzzle and tracks. Keep it a single vehicle with no ground shadow, scenery, markings, flags, lettering, or insignia.
```

## v3 · 2026-11-12

Built-in ImageGen edit. [Concept v3](concept-v3.png) is a static 1254 × 1254 RGBA sprite.

- Image 1 is [concept v2](concept-v2.png), the edit target.
- Image 2 is [concept v1](concept-v1.png), the turret proportions reference.

```text
Use case: precise-object-edit
Asset type: one transparent square map sprite of a fictional modern tracked tank for FightLines.
Image 1 is concept v2 and the edit target. Image 2 is concept v1 and a reference only for the smaller, centered turret proportions and height. Replace only the turret shell, roof fittings, and the small joint where the existing barrel attaches to the turret.

Draw a compact turret with the quiet, sturdy silhouette of a Tiger I turret reinterpreted as present-day game art. Use a single broad, almost flat roof, slightly chamfered upper shoulders, a deep near-vertical side with a subtly curved rear corner, and a short rounded rectangular mantlet visibly cradling the barrel root. Make the turret feel like one coherent mass. In this right-facing view, pull the rear wall well forward from the huge overhang on image 1 so it sits roughly over the rear third of the hull like image 2. Bring the whole turret into a compact central silhouette, with enough height to fill the tile like image 2. On the roof include one restrained low round hatch and a single small flush optical slit in subdued blue-gray. The turret's front ends in a blunt, rounded armor shoulder and the barrel joint. Remove the huge triangular cheek, sweeping diagonal shadow, and pointed wedge. Keep shapes clean and believable, without tall sensor towers, large paired windows, extra barrels, or a bulbous muzzle. Keep the existing plain barrel horizontal, pointed right, with its length and muzzle position close to image 1.

Preserve image 1's entire hull below the turret ring, including the steep sloped front glacis and its edge highlights, side skirts, running gear, road wheels, tracks, storage boxes, rear cylinder, and lower silhouette. Preserve the camera, pose, scale, and existing field-gray palette and lighting. High-detail hand-painted 1980s anime mechanical art with dark ink contours, broad cel-shaded planes and subtle painted highlights. Keep the image square with real alpha transparency, with the complete barrel and tracks visible inside the canvas. Isolated static sprite without scenery, ground shadow, crew, emblems, flags, or lettering.
```

The second edit used the first v3 draft as image 1 and concept v2 as image 2. It raised the turret roof to recover the sprite's vertical footprint.

```text
Use case: precise-object-edit
Asset type: one right-facing fictional modern tank sprite on transparent square canvas for FightLines.
Image 1 is the first v3 draft. Its compact Tiger I–inspired turret design is approved for this refinement. Image 2 is v2, for exact placement of the lower hull and tracks and overall vertical framing.

Keep image 2's entire lower hull and tracks in their exact positions and sizes, including the sloped nose and exposed front track. Place the compact turret from image 1 onto that original turret ring. Keep its same width, centered position, nearly flat roof, curved rear corner, blunt small rounded mantlet, one low circular hatch, and one small recessed optical slit. Keep the slim plain horizontal right-facing barrel and end it at the same horizontal position. Raise the roofline modestly by adding depth to the body of the same turret, so the top of its low hatch lies around 12 to 14 percent from the top of the canvas and the lowest tracks about 6 to 7 percent from the bottom. Preserve the quiet recognizable turret design. Keep its roughly vertical side and gently chamfered corners. Omit the large wedge and overhang of image 2. Maintain the right-facing near-side-on angle, full tile-filling width and all four clear edges.

Keep the field-gray armor and strong ink contours with the same hand-painted 1980s anime cel shading. Single isolated vehicle on true alpha transparency, no scenery, shadow, lettering, emblems, flags, or crew.
```

## v4 · 2026-11-12

Built-in ImageGen edit. [Concept v4](concept-v4.png) is a static 1254 × 1254 RGBA sprite.

- Image 1 is the first v3 draft selected for markup, saved by ImageGen as `exec-b7a65292-d982-46a8-b41e-baa91c85343b.png`.
- Image 2 is the [high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), used as the barrel reference.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Edit image 1, the exact right-facing tank draft marked up by the art director. Image 2 is the original neutral tank, solely a shape reference for the barrel. Apply these four specific edits.

1. Barrel at the upper right. Replace the long slim plain tube with the original neutral tank's short, thick, stepped barrel silhouette. Match image 2's visual proportions closely: broad band at the root, narrower central span, raised narrow collar and a wide blunt ringed muzzle with a dark bore at the right. Keep the same compact rightward reach, fully inside the canvas, and use image 1's field-gray paint and cel shading on the new barrel.
2. Turret side toward the front, near 66 percent from the left and 38 percent down. Keep the compact squarish silhouette, flat roof, low round hatch, and small modern optic from image 1. Break up the very large flat side plate with distinctive Panzer IV–inspired geometry: a broad central plate, an angled front corner that turns inward toward the barrel, a visible oblique seam, and a small chamfered lower-front facet. Use crisp ink seams and differing light values to make those facets visible on a map tile. Keep the turret a compact squared mass, with moderate, believable angles and no protruding wedge.
3. Sloped front hull near 93 percent from the left and 65 percent down. Keep one big continuous diagonal glacis plane and extend its pointed lower lip forward to overlap the upper leading shoulder of the track where the links first curve down. The big diagonal plane itself should run farther forward over that exposed top-front stretch. Keep the vertical front run of links and the drive wheel readable below the armor. Avoid adding a separate box or a second slope.
4. Rear hull near 19 percent from the left and 48 percent down. Remove the horizontal cylindrical canister, its straps and supporting pipe. Fill that space with a low squared continuation of the existing field-gray hull armor, with a flat top deck, broad side plate and one restrained seam. Keep it within the existing vehicle footprint.

Preserve the exact right-facing near-side-on view, level track run, wheels, compact proportions, flat turret roof, and large tile-filling footprint. Keep the warm field-gray and charcoal palette, confident ink contours and high-detail hand-painted 1980s anime cel shading. Use a square canvas with true alpha transparency and a thin clear margin around the full muzzle, hull and tracks. Show a single isolated vehicle. No background, ground shadow, crew, marks, emblems, flags, or text.
```

## v5 · 2026-11-12

Built-in ImageGen edit of [concept v4](concept-v4.png). [Concept v5](concept-v5.png) adds a small rear turret overhang with clearance above the rear deck.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines map sprite.
Edit the attached concept v4 with one small silhouette change at the lower rear of the turret, around x 29%, y 39%. The tank faces right, so the turret rear is its left edge.

Give the turret a small squared rear overhang, like a compact integral stowage bustle. Use the existing rear side plate as the starting point. Let its rear lip project only slightly left and end higher than the hull deck. Cut the lower rear turret corner inward toward the existing turret ring, so a short, clean notch of actual transparent negative space opens directly under the overhanging lip and above the rear hull deck. This should read as a modest shelf hanging above the deck, with a small clear gap open to the left, about 3 to 4 percent of the canvas in height. The ring and the main turret remain solidly connected to the hull. Use a short horizontal underside and a simple angled transition into the ring. Keep the overhang substantially inboard of the rear fender and rear end of the tank. No detached item or oversized extension.

Preserve the existing rest of the sprite as closely as possible, especially the chunky ringed right-facing barrel, square faceted turret front and side, hatch and optic, single long front glacis, squared rear hull plate, all tracks and wheels, the framing and the right-facing near-side-on angle. Keep field-gray colors and the same hand-painted 1980s anime ink contours and cel shading. Keep the complete tank on a transparent square with no scenery, lettering or background.
```

## v6 · 2026-11-12

Built-in ImageGen edit of [concept v5](concept-v5.png). [Concept v6](concept-v6.png) aligns the rear turret panel edges at the roof bevel.

```text
Use case: precise-object-edit
Asset type: a single transparent FightLines map sprite.
Edit the attached concept v5. Make one localized geometry correction to the upper rear corner of the turret, around x 25%, y 28%. The tank faces right, so the rear is on the left.

Keep the exterior silhouette of this corner. Inside it, make the sloping roof bevel, the narrow rear-facing armor facet and the broad near-side armor panel meet as a single coherent three-plane corner. Start the rear/side crease exactly where it meets the roof bevel, then continue it as one clean, straight edge toward the existing lower chamfer. Make the highlights and shadows terminate at that same junction. Remove the doubled, offset kink and the dark trapped sliver where the current bevel and panel edges nearly meet. The large near-side plate should remain broad and readable. Show the rear facet at a slightly darker tone and keep the roof bevel lighter, under the same lighting. Keep the existing low circular hatch and small optic and the short rear overhang with transparent clearance above the hull.

Preserve the full exterior silhouette, right-facing angle, tile coverage, barrel and muzzle, front turret facets, long glacis, hull, wheels, tracks, existing colors and painted 1980s anime finish. Keep the change confined to the rear turret panel junction and its highlights. Output the complete square sprite with genuine alpha transparency, no backdrop, no ground shadow, no markings or lettering.
```

## v7 · 2026-11-12

Built-in ImageGen edit of [concept v6](concept-v6.png). [Concept v7](concept-v7.png) is the stepped, flat-front hull alternative. Image 2 is the supplied Tiger I screenshot, `Screenshot 2026-11-12 at 2.20.08 AM.png`.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Image 1 is concept v6, the exact tank to edit. Image 2 is a Tiger I reference used only for the stepped shape of the front hull beneath the turret. The reference faces left; the edited sprite must continue to face right. Do not copy the reference's paint, numbers, insignia, turret, or barrel.

Make a hull-front alternative with a distinctly blunt Tiger I–inspired profile. Replace only the current large sloped front glacis, at the right underneath the barrel, with three broad planar surfaces that read as horizontal, vertical, horizontal in profile. Extend the level upper hull deck toward the nose. End it with a sharp break into a broad, nearly upright flat front armor face. The face should visibly drop straight down in the side silhouette. At its foot, make a clear right-angle turn into a second level shelf that projects forward over the leading bend of the right track. The lower shelf should reach about as far right as the existing v6 armor tip. Show the distinct level top edges and a darker front-facing plane appropriate to the existing slightly elevated camera. Put the vertical step sufficiently far back from the track nose that the lower shelf is clearly visible. Make the corners crisp and the major planes clean enough to read on a 32 px tile. Allow only thin edge bevels, no long diagonal slope or pointed wedge. Do not add historical equipment or clutter. Keep the design modern, field-gray, and visually consistent with the rest of the hull.

Retain image 1's right-facing viewpoint, complete framing, tile-filling size, road wheels and tracks, rear hull, turret including its rear panel alignment and overhang gap, hatch, optic, and chunky ringed barrel. Preserve the high-detail 1980s hand-painted anime linework, painted cel shading and existing palette. Keep the entire vehicle inside a square canvas with genuine alpha transparency. A single isolated sprite without text, decals, emblems, people, ground shadow, or scenery.
```

## v8 · 2026-11-12

Built-in ImageGen edit of [concept v7](concept-v7.png). [Concept v8](concept-v8.png) raises the lower front shelf to make the step shallower.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines map sprite.
Edit concept v7. Make one localized change to the stepped front hull at the right below the barrel. The bottom step currently sits too low. Raise the horizontal top surface of the projecting lower nose shelf so the vertical drop from the upper deck to that shelf is approximately half as tall as it is in the input. Keep the upper deck and its front edge at their current height. As a visual landmark, the raised shelf's near edge should sit about level with the top of the nearest rectangular track skirt, rather than near the bottom of that skirt.

Keep the two horizontal surfaces distinct, with a short upright flat armor face between them. Keep the nose shelf projecting forward to the same rightmost position. Fill beneath the raised shelf with a clean, solid flat-sided continuation of the front hull down to the existing front track guard, keeping the silhouette over the leading track intact. The result should look like a shallow step in one coherent armored hull, not a thin low ledge or a floating slab. Use the existing perspective and controlled light-to-dark edge shading. No broad slope, wedge or added hardware.

Preserve the rest of the sprite as closely as possible, including the field-gray turret with rear overhang, ringed barrel, rear hull, side skirts, tracks and wheels, right-facing viewing angle, tile footprint and high-detail 1980s anime cel shading. Output one complete square sprite with real alpha transparency, no backdrop, shadow, emblems or text.
```

## v9 · 2026-11-12

Built-in ImageGen edit of [concept v8](concept-v8.png). [Concept v9](concept-v9.png) foreshortens the faces of the stepped front and adds an inset panel and running light.

```text
Use case: precise-object-edit
Asset type: one transparent FightLines map sprite of a fictional modern tank.
Edit concept v8, focused on the shallow front hull step under the barrel near x 87.5%, y 50.5%. Keep the current step height and its flat–upright–flat profile.

Correct the perspective of this local hull assembly. Match the existing near-side-on, slightly elevated viewpoint of the turret and treads. The broad side of the tank should dominate. Foreshorten the dark front-facing plane of the upper step so it reads as a narrow sliver at the right, less than half its current apparent width. Do the same for the short right-facing face of the lower shelf. Keep a slim amount of the top surfaces visible. Align the bevels and crosswise seams to the same shallow perspective. Keep the silhouette horizontal, then vertical, then horizontal in profile, with the same tall upper deck and short raised nose shelf. Do not rotate, flip, or reframe the tank.

Give this front step a little purposeful visual detail. On the visible near-side shoulder just behind the step, add a small inset angular armor panel with a short diagonal return and two restrained fasteners, and a single compact recessed amber running light tucked under the step's bevel. Blend these into the existing armor seams and use dark ink and clear values so they read at tile scale. Keep most of each plane clean. Keep the front blunt with no long sloped glacis, no bulky external fixture and no extra weapon.

Preserve the rest of the right-facing sprite as closely as possible, including the turret shape and rear overhang, the compact ringed barrel, rear hull, wheel and tread silhouette, tile scale, field-gray palette, and high-detail hand-painted 1980s anime cel shading. Keep the entire vehicle on a transparent square canvas. No backdrop, text, markings or ground shadow.
```

## v10 · 2026-11-12

Built-in ImageGen edit of [concept v9](concept-v9.png). [Concept v10](concept-v10.png) moves the turret forward and squares the rear fender while keeping the stepped front.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Edit concept v9. Preserve the square, flat-sided, modern Tiger I–inspired style. The vehicle should read unambiguously as facing right from its hull proportions as well as from the barrel. Make a modest, controlled silhouette correction.

Move the whole existing turret shell and its ring forward, to the right, by roughly 5 to 6 percent of the square canvas. Keep the turret shell the same size, height and shape, including the hatch, optic, rear panel alignment and small overhang with a clear gap under it. This move should leave a little more visible rear deck to the left and less upper deck extending to the right beneath the barrel. Keep the barrel pointing right at the same height. Hold the muzzle tip at approximately its existing canvas position, with a comfortable clear margin, by slightly shortening only the exposed plain middle section of the barrel. Keep the original fat stepped rings, dark bore, and chunky neutral-tank muzzle silhouette intact.

At the rear of the hull on the left, replace the long diagonal trailing fender with a short squared fender that relates to the blunt front armor. Keep a shallow corner bevel for track clearance. The left end should read as a simple, squared-off rear under the exposed deck. The right end stays visibly forward with its existing shallow vertical step, lower shelf above the lead tread, inset panel and recessed amber light. Keep the two level planes of the step and its narrow front-facing facet. No new hull slope or extra hardware.

Keep the existing wheel and track geometry and footprint, exact near-side-on right-facing viewing angle, field-gray palette, and high-detail 1980s hand-painted anime ink contours and cel shading. Preserve the complete silhouette inside a square with genuine transparency. One isolated vehicle, no background, ground shadow, emblems, or text.
```

## v11 · 2026-11-12

Built-in ImageGen edit. [Concept v11](concept-v11.png) combines [concept v10](concept-v10.png), the first input, with the [high-resolution neutral tank](../../../artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png), the second input.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Make one new hybrid concept using both references. Image 1 is concept v10 and provides the square Tiger I–inspired architecture, silhouette balance and placement. Image 2 is the original high-resolution neutral FightLines tank and provides the rounded industrial armor treatment, dark running gear and olive-gray painted surfaces. The hybrid should show recognizable visual features of both inputs.

Retain image 1's forward-set square turret with the small rear overhang and visible clearance above the deck. Retain the blunt stepped front hull on the right: level upper deck, short near-vertical drop with a narrow visible front face, and level lower shelf over the leading track. Keep the squared rear, balanced deck lengths, plain low round hatch, and small amber marker toward the right. Preserve the established right-facing, near-side-on angle and the current forward read.

Borrow image 2's chunky radiused bevels and stepped armor thickness. Keep the turret's broad near-side facet and diagonal front cheek, but give the cheek and barrel mount the neutral tank's thick wraparound shoulder and clearer rounded edge lighting. Integrate one low armored blue-gray optic into the roof profile. Keep the familiar short, broad stepped barrel with a ringed muzzle, fully in frame. Below the horizontal step, give the right track guard one compact rounded corner around the leading tread, echoing image 2 while leaving the upper front step visibly square. Keep the left fender squared so the two ends read correctly. Make the side skirts feel like substantial individual bolted plates with neutral-style rounded bevels. Keep the existing road-wheel positions, wheelbase and track silhouette. Use muted olive-gray armor midway between the references, charcoal tracks, warm metallic edge highlights, and readable painted cel-shaded planes.

High-detail hand-drawn 1980s anime mechanical illustration with confident dark contours, clear shapes at 32 and 64 px, restrained painted wear. The complete single vehicle should fill a square tile with a thin transparent margin around the tracks and muzzle. True alpha transparency. No scenery, shadow, crew, text, decals, emblems, or flags.
```

## v12 · 2026-11-12

Built-in ImageGen edit of [concept v11](concept-v11.png). [Concept v12](concept-v12.png) thickens the barrel and ringed muzzle.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines map sprite.
Edit concept v11. Make exactly one visual change: fatten the existing right-facing barrel. Enlarge the outside diameter of the barrel along its existing horizontal centerline. Make the narrow middle span roughly 25 percent thicker and the broad ringed muzzle roughly 15 percent thicker, so the whole barrel looks visibly heavier and its stepped profile still reads clearly at map scale. Keep the thick collar, stepped rings, wide dark bore, and chunky proportions. Keep the same horizontal length, near-side-on view, muzzle tip position and margin from the right edge. Blend the larger barrel into the existing mount with the same warm olive-gray metal, rounded bevels, and painted highlights.

Preserve the rest of the sprite as closely as possible, including the turret armor and overhang, hull step, amber light, front fender, side skirts, rear hull, wheels, tracks, colors, right-facing angle, and full framing. Keep the high-detail hand-painted 1980s anime illustration. Output one complete vehicle on a square canvas with genuine alpha transparency and no backdrop, text, marks or shadow.
```

## v13 · 2026-11-12

Built-in ImageGen edit of [concept v12](concept-v12.png). [Concept v13](concept-v13.png) is the more Tiger I–inspired alternative. Image 2 is the supplied Tiger I screenshot, `Screenshot 2026-11-12 at 2.20.08 AM.png`.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Image 1 is concept v12, the edit target. Image 2 is the user's Tiger I screenshot, a visual reference for the heavy turret shoulder, barrel collar and blunt stepped nose. It faces left. The sprite must keep facing right. Do not copy any markings or numbers from it.

Create one bolder Tiger I–inspired alternative that stays in the same fictional modern FightLines art style. Make these visual changes unmistakable without changing the tank's footprint.
- Turret: turn the long side into a single thick, mostly upright armor mass with a gently rounded horseshoe-like rear corner, a level roof, a small offset round commander's cupola with dark inset vision blocks, and a broad rounded-rectangular mantlet at the right. Give the mantlet a noticeable tall face wrapping around the thick barrel root. Reduce the angular front cheek just enough to make the mantlet the main feature. Preserve the small rear overhang and the gap above the deck. Keep a small low modern blue-gray optic. Preserve v12's fat, short, ringed barrel, muzzle profile and reach.
- Hull: keep the flat upper deck, narrow upright front riser and raised lower front shelf as the right-facing nose. Give the front a thick, clean slab-armor edge and a compact squared mudguard with only a small bevel over the leading track. Retain the inset amber light as a subtle modern detail. Keep the rear squared and keep the turret forward over the same wheelbase.
- Running gear: replace the clearly separated big wheel discs with a row of large overlapping dark steel wheel discs, using alternating light rims and partially hidden rims as a simple visual echo of the Tiger I. The discs should read as a dense rhythm at map scale. Keep the outer tread profile, ground contact, front sprocket and rear idler position, and the footprint exactly where they are.

Retain the v12 olive-gray field color, charcoal running gear, bold ink contours, painted cel shading, and high-detail 1980s anime mechanical illustration. Match v12's near-side-on, slightly elevated right-facing camera. Draw the full barrel and track silhouette inside a square with real alpha transparency and a thin clear margin. No scenery, ground shadow, people, text, markings, flags, or emblems.
```

## v14 · 2026-11-12

Built-in ImageGen edit of [concept v13](concept-v13.png). [Concept v14](concept-v14.png) develops the Tiger I–inspired turret and slab-sided chassis. Image 2 is the supplied Tiger I screenshot, `Screenshot 2026-11-12 at 2.20.08 AM.png`.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite of a fictional modern tank.
Image 1 is concept v13, the edit target. Image 2 is the user's Tiger I screenshot, a visual reference for the upright turret wall, rounded barrel mount, straight hull side and continuous narrow fender line. The photograph faces left; keep the sprite facing right. Use only its visual shapes. Do not copy the photograph's paint, numbers, markings, or emblems.

Make the turret and chassis more recognizably Tiger I–inspired while preserving the stylized FightLines scale and modern finish.

Turret: redesign v13's elongated side into a slightly shorter, compact horseshoe-shaped turret. Pull the left rear edge inward a little and give the upper and lower rear corners a more pronounced, smooth wrap into the side. Draw a single upright armor wall under a low flat roof, with a clean curved rear seam and a short rear overhang above the ring. Replace the oversized pair of face bolts with a restrained circular detail near the rear and a very subtle weld line. Keep the small rear-offset round commander's cupola with narrow dark vision slits. Give the front a broad, softly rounded rectangular mantlet that reads as a distinct heavy collar plate, with its vertical edge and contrasting shadow clearly visible. Retain the tiny modern optic and keep the thick, compact stepped ringed barrel pointing right, with its current centerline and muzzle position.

Chassis: replace the row of separate chunky armor boxes and deep rectangular track skirts with one long continuous, upright flat side armor slab under the turret and a much shallower straight fender strip immediately over the tracks. Give the slab a simple level upper edge, very few understated panel divisions, and subtle edge highlights. Keep the rear squared. At the right, give the upper hull a distinct narrow upright front plate with one small recessed dark vision slit near its corner, and a short level lower shelf extending forward over the leading tread. Keep the front profile clearly horizontal, vertical, then horizontal, without a large diagonal slope. Preserve a tiny recessed amber light as the modern accent. At the very front and rear, use small squared fender caps with slight corner bevels. Let the shallow strip expose more of the top tread and the overlapping road wheel pattern without changing the wheels or the outer track geometry.

Preserve the established right-facing near-side-on, slightly elevated view and wheelbase, the square tile-filling footprint, tight margins, the olive-gray and charcoal palette, and detailed hand-painted 1980s anime ink contours and cel shading. Keep broad shapes readable at map scale. Draw one complete vehicle on a transparent square canvas. No background, floor shadow, text, crew, flags, or insignia.
```

## v15 · 2026-11-12

Built-in ImageGen edit of [concept v14](concept-v14.png). [Concept v15](concept-v15.png) thickens the barrel shaft while retaining the existing muzzle size.

The first pass produced a subtler change.

```text
Use case: precise-object-edit
Asset type: one static transparent FightLines game-map sprite.
Edit the selected German tank concept v14. The only requested change is the drawn barrel shaft between the large collar beside the turret and the ringed muzzle at the right. The current center shaft is too thin relative to the muzzle. Thicken the exposed narrow middle section visibly, aiming for about 25 to 30 percent more exterior diameter in the illustration. Expand both the upper and lower edges around the same horizontal centerline. Adjust the adjacent small shaft step or collar only as needed to make the transition look natural. Keep enough contrast in the stepped silhouette to read at 32 and 64 px.

Keep the entire muzzle at its original size and location, including the outer rim and dark bore. Keep the existing barrel length, direction, warm olive-gray paint, rounded bevels, ink contours, and cel highlights. Leave the mantlet, turret, roof fittings, stepped hull, fender, tracks, wheels, and the rest of the artwork as close to the original as possible. Use the same square framing and genuine transparent alpha background. No scenery, ground shadow, markings, or text.
```

The second pass used v14 as the edit target again.

```text
Use case: precise-object-edit
Edit the attached approved FightLines tank v14 sprite. Preserve the exact sprite, pose, palette, inked painted finish, and transparent square framing. Make a strong, clearly visible change to only the narrow exposed barrel shaft between the turret-side sleeve and the large ringed muzzle. The result should no longer look like a big muzzle on a skinny neck.

The shaft is the short central span at roughly 79–82% of the canvas width, directly left of the muzzle's first thin ring. The existing shaft looks about three fifths as tall as the muzzle. Redraw it to look about four fifths as tall as that same muzzle. Push its upper outline upward and its lower outline downward by a clearly visible amount, symmetrically about the existing centerline. Bring the sleeve immediately to the left of that shaft smoothly into the thicker shape. Maintain one shallow step into the original rim. Keep the barrel horizontal and maintain its exact length. Lock the broad rightmost muzzle block, dark bore, rim, size and position to the reference. Keep the large barrel mounting plate at the turret, turret itself, chassis and tracks as close to the source artwork as possible. Keep the complete right-facing vehicle on real alpha, with no scenery, floor shadow, emblems or lettering.
```
