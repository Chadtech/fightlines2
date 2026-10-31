const { execFileSync } = require('node:child_process');
const { readFileSync, writeFileSync, statSync } = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const source = 'public/backdrop-calibrations.json';
const destination = 'src/Game/CombatTheaterCalibrations.elm';
const unitKinds = ['Infantry', 'Tank', 'FieldGun', 'Truck'];
// Keep the authoring boundary consistent with src/backdrop_calibration.rs.
const fields = {
  frontFooting: [55, 98],
  rowSpacing: [0, 26],
  unitSize: [12, 40],
  rearScale: [35, 100],
  trenchFooting: [25, 98],
  trenchSize: [10, 45],
  secondTrenchFooting: [25, 98],
  secondTrenchSize: [10, 45],
};

function object(value, context) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${context}: expected an object`);
  }
  return value;
}

function calibration(stored, context) {
  object(stored, context);
  for (const field of Object.keys(stored)) {
    if (!Object.hasOwn(fields, field)) throw new Error(`${context}: unknown field ${field}`);
  }
  const values = {
    ...stored,
    trenchFooting: stored.trenchFooting === undefined ? 86 : stored.trenchFooting,
    trenchSize: stored.trenchSize === undefined ? 35 : stored.trenchSize,
  };
  values.secondTrenchFooting = stored.secondTrenchFooting ?? values.trenchFooting;
  values.secondTrenchSize = stored.secondTrenchSize ?? values.trenchSize;
  for (const [field, [minimum, maximum]] of Object.entries(fields)) {
    const value = values[field];
    if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum) {
      throw new Error(`${context}.${field}: expected a number between ${minimum} and ${maximum}`);
    }
  }
  return values;
}

function render(catalog, assetExists) {
  object(catalog, source);
  const entries = [];
  for (const backdrop of Object.keys(catalog).sort()) {
    if (!/^\/assets\/combat-backdrops-anime-v1\/[A-Za-z0-9.-]+\.png$/.test(backdrop)
        || backdrop.includes('..')) {
      throw new Error(`Invalid backdrop path: ${backdrop}`);
    }
    if (!assetExists(backdrop)) throw new Error(`Backdrop does not exist: ${backdrop}`);
    const stored = object(catalog[backdrop], backdrop);
    // Legacy shared settings apply to every unit, matching the editor loader.
    const shared = Object.hasOwn(stored, 'frontFooting');
    if (!shared) {
      for (const kind of Object.keys(stored)) {
        if (!unitKinds.includes(kind)) throw new Error(`${backdrop}: unknown unit kind ${kind}`);
      }
    }
    for (const kind of unitKinds) {
      if (!shared && !Object.hasOwn(stored, kind)) continue;
      const values = calibration(shared ? stored : stored[kind], `${backdrop} (${kind})`);
      const settings = Object.keys(fields).map(field => `${field} = ${values[field]}`).join('\n, ');
      entries.push(`{ backdrop = ${JSON.stringify(backdrop)}\n, unitKind = UnitKind.${kind}\n, calibration = { ${settings}\n}\n}`);
    }
  }
  const list = entries.length ? `[ ${entries.join('\n, ')}\n]` : '[]';
  return `module Game.CombatTheaterCalibrations exposing (catalog)

{-| Generated from ${source} by make combat-theater-calibrations.
Do not edit this module manually; save changes in the backdrop reviewer.
-}

import Api.Enum.UnitKind as UnitKind
import Game.BackdropCalibration exposing (Entry)


catalog : List Entry
catalog =
${list}
`;
}

function main() {
  const catalog = JSON.parse(readFileSync(path.join(root, source), 'utf8'));
  const elm = render(catalog, backdrop => {
    try {
      return statSync(path.join(root, 'public', backdrop)).isFile();
    } catch (error) {
      if (error.code === 'ENOENT') return false;
      throw error;
    }
  });
  // Format before replacing the output so failures leave the previous module intact.
  const formatted = execFileSync('elm-format', ['--stdin'], { input: elm, encoding: 'utf8' });
  const output = path.join(root, destination);
  let previous;
  try {
    previous = readFileSync(output, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (previous !== formatted) writeFileSync(output, formatted);
  console.log(`Generated ${destination} from ${source}.`);
}

module.exports = { render };

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
