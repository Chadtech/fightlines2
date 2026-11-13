# Imperial Japan tank concepts

The approved static concept is [concept-v4.png](concept-v4.png).

Generated with the built-in ImageGen editor using transparent background mode.

## Concept v1 design pass

Inputs in order:

1. Neutral tank source at `artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png`.
2. [Official JGSDF Type 10 photograph](https://www.mod.go.jp/gsdf/wae/gsdf-wae_boshu/item/images/ph_gsdf_pickup_hitomarushiki.jpg).
3. Approved Imperial Japan infantry at `design/infantry/imperial-japan/concept-v13.png`.

```text
Use case: stylized-concept. Edit image 1 into a single Imperial Japan tank map sprite for FightLines. Treat image 1 as a silhouette underdrawing: keep its almost side-on, right-facing camera angle, level tracks, overall scale, and compact, broadly square tank mass. Repaint the exterior completely so the vehicle reads as a distinct modern Type 10-inspired variant. Image 2 supplies the Type 10 visual language: compact faceted cheek armor narrowing to a forward wedge, crisply aligned modular side plates, low flush fittings. Image 3 supplies the warm muted olive-khaki faction colors only.

Give it a clearly forward-thrusting arrowhead turret side with a shallow wedge profile over a relatively tall square-bodied hull and a broad dark track band. Replace the neutral tank's stack of square optics with one low-profile recessed dark optical strip and a compact hatch. Use a slim, simple horizontal barrel with a small plain muzzle, short enough that the barrel tip ends near the front edge of the track rather than sticking far out. Replace the exposed rear cylinder with a flush paneled rear hull. Use tightly fitted swept armor seams, narrow chamfered edges, and a sharply raked right-hand nose. Keep the broad continuous tread outline and leave the road wheels readable. The lighter-looking planes should make the tank look ready to spring forward while parked. Use the neutral for proportions and framing only, with the shape and surface treatment visibly redesigned.

Match the neutral canvas framing: on the transparent square, center the whole silhouette with about 5% clear margin at the left, 3% at the right, 9–12% above and 7% below. Keep enough turret and hull height for a roughly square overall silhouette. Whole barrel and both ends of the tracks inside the canvas. View almost entirely from the side, with only a small glimpse of the top surfaces, no deep three-quarter perspective. One vehicle at rest.

High-detail hand-painted 1980s Japanese anime mechanical cel artwork. Variable-weight dark ink contours, sharp cel-shaded light and shadow planes, deliberate small hand-painted highlights and wear. Restrained warm gray-olive and sand-khaki armor, dark charcoal tracks and slate optic glass. Keep big separated shapes legible in a small map tile. True transparent alpha background; no crew, lettering, logos, cast shadow, ground, smoke, effects, scenery, border, or layout text.
```

## Concept v1 silhouette pass

Inputs in order:

1. Design pass output saved by ImageGen at `~/.codex/generated_images/01a1ce70-8257-7373-bfad-88e1b74e5de6/exec-cb45b706-002b-4de9-b42b-a1c9257efdb1.png`.
2. Neutral map master at `artwork/units/illustrated/rigged/tank-neutral.png`.

```text
Use case: precise-object-edit. Edit the first attached image, the Imperial Japan tank concept, into the final static FightLines map sprite. The second image is the neutral map sprite for silhouette scale and placement. Keep the first tank's Type 10-inspired forward wedge, tightly fitted directional armor panels, restrained olive-khaki palette, low optical strip, simple horizontal right-pointing barrel and 1980s hand-painted anime cel style. Preserve its exact almost side-on right-facing view.

The current concept looks a bit too low and flat next to the neutral tank. Make the first tank visibly taller while keeping its present width and its square frame. Extend the tread base and larger road wheels a little lower, deepen the upper hull's raked front and side planes a little, and extend the turret body higher while keeping the cap and optics flush. Redraw the proportions naturally, with the same thin, sharp, forward-raked armor surfaces and compact barrel. The barrel can be a little bolder in outline so it survives downsampling. The focus is on silhouette and framing, retaining the first image's design identity. The neutral tank is solely a scale and placement reference.

The final full tank should fill approximately 92% of the square canvas in width and about 81% in height, with approximately 10% transparent margin above the turret and 8% below the tracks. This means the top of the turret rises clearly into what is presently blank space. Place the entire right-pointing muzzle and full continuous treads inside the square, with about 4% clear margin at each side. Large and nearly square, isolated on true transparent alpha. Keep painted cel shadows and dark contours legible at map scale. Single stationary tank only, with no cast shadow, scenery, effects, crew, lettering, or logos.
```

## Concept v2 edits

Edited the render attached in the review, saved by ImageGen at `~/.codex/generated_images/01a1ce70-8257-7373-bfad-88e1b74e5de6/exec-bf9798a0-20e0-4e9c-921b-45407ec528d2.png`.

```text
Use case: precise-object-edit. Edit the attached olive-khaki right-facing FightLines tank sprite in four localized areas. Use the attached image as the edit target. Work in its existing high-detail, inked and painted 1980s anime cel style.

1. Simplify the turret roof around x36%, y9%. Remove the tall stack of boxes, separate blue-eyed sensor pod, and little raised fittings above the main faceted turret armor. Replace the clutter with one clean, integrated slab of roof armor, stepped shallowly into the main turret, with at most a single flat hatch seam. Keep some height through the turret's own continuous armor shape so the sprite still reads as a substantial, nearly square tank.
2. At the front right of the hull around x88%, y50%, remove the orange circular light and its entire projecting rectangular housing. Continue the adjacent sloped khaki armor surface through the area, leaving a clean wedge and no replacement light.
3. On the mid-hull side near x60%, y53–57%, remove the whole protruding shiny silver rectangular three-segment fixture immediately above the track skirt. Continue the same uninterrupted olive-khaki plate surface behind it with the original surrounding panel boundaries.
4. At the left rear of the hull near x19%, y49–55%, remove the strapped horizontal cylindrical canister and the exposed pipe immediately below it. Replace them with a substantial boxy engine housing integrated into the hull, using straight-sided rectangular armor, a chamfered top corner, and a few dark recessed cooling louvers. The single solid rectangular shape should read as an armored engine compartment at map tile size.

Keep the rest of this exact tank, including its right-facing profile, level tracks and road wheels, front wedge, major turret side planes, barrel shape and position, muted olive and khaki colors, outlines and cell shading. Keep the same large footprint and registration within the square, with the muzzle and tracks fully visible. A single static tank with true transparent alpha throughout the background, no ground, shadow, people, lettering, or added fixtures.
```

## Concept v3 optic edit

Edited `design/tanks/imperial-japan/concept-v2.png`.

```text
Use case: precise-object-edit. Make one localized edit to the attached Imperial Japan v2 tank sprite for FightLines. The tank's front is on the right, toward the barrel. In the low armored turret roof near x54%, y18–22%, remove both wide, silver-framed blue viewports. Restore a solid continuous olive-khaki armor plate across the entire broad left-to-right side wall that faces the viewer. Add just one small, understated dark-glass sight recessed into the narrow, angled forward-facing bevel at the right end of that same raised roof armor, near x62%, y19%. The face of the sight should point toward the muzzle, aligned with that forward bevel. In this near-side view, the glazing is only a narrow foreshortened dark trapezoid on the right-facing plane, with a clear armor fold separating the bevel from the plain side wall. Keep it flush with the roof armor and visually small, with a muted slate reflection and a thin dark border.

Preserve the existing low roof shape and hatch seam, side-on right-facing camera angle, silhouette, barrel, tracks, engine housing, all other hull details, and placement inside the square. Match the existing high-detail 1980s anime cel shading and ink lines. A single vehicle on true transparent alpha, with the entire silhouette in frame.
```

## Concept v4 palette match

Edited `design/tanks/imperial-japan/concept-v3.png` with `artwork/units/illustrated/rigged/tank-box-removal/tank-neutral-source.png` as the color reference.

```text
Use case: precise-object-edit. Recolor Image 1, the approved Imperial Japan v3 FightLines tank concept. Image 2, the original neutral tank, is solely a palette reference. Make the paint of Image 1 closely match the neutral tank's muted military yellow-olive green. Its broad armor midtones are around #7c7845 and #787544. Shift the current sandy brown and tan armor on the turret, hull, skirts, rear engine housing, and barrel to that olive family. The broad lit facets should stay olive, with the neutral reference's pale yellow-olive color reserved for the strongest edges. Give the deep shade the reference's dark olive cast, and harmonize the painted wheel hubs with the neutral reference's darker bronze olive. Keep the steel tread pads and rims gray, the rubber and ink charcoal, and the single recessed forward-facing optic subdued slate blue.

This is a color-only pass on Image 1. Copy its exact shape and placement, near-side view, armor facets, shading boundaries, linework, proportions, tracks, horizontal barrel, rear engine vents, hatch seam, and single optic on the right-facing bevel. Preserve its high-detail 1980s anime cel art and the same true transparent square canvas with the complete sprite fully visible. Use no geometry or details from Image 2.
```
