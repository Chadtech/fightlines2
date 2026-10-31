const assert = require('node:assert/strict');
const { test } = require('node:test');
const { render } = require('./build-combat-theater-calibrations.cjs');

const backdrop = '/assets/combat-backdrops-anime-v1/plains.png';
const settings = { frontFooting: 82, rowSpacing: 10, unitSize: 18, rearScale: 65 };
const exists = () => true;

test('legacy shared settings expand to all units and inherit trench settings', () => {
  const elm = render({ [backdrop]: { ...settings, trenchFooting: 70, trenchSize: 28 } }, exists);
  assert.equal((elm.match(/unitKind = UnitKind\./g) || []).length, 4);
  assert.equal((elm.match(/secondTrenchFooting = 70/g) || []).length, 4);
  assert.equal((elm.match(/secondTrenchSize = 28/g) || []).length, 4);
});

test('per-unit settings preserve missing units and independent trench values', () => {
  const elm = render({ [backdrop]: { Infantry: { ...settings, secondTrenchSize: 22 } } }, exists);
  assert.match(elm, /unitKind = UnitKind.Infantry/);
  assert.doesNotMatch(elm, /UnitKind.Tank/);
  assert.match(elm, /trenchFooting = 86/);
  assert.match(elm, /trenchSize = 35/);
  assert.match(elm, /secondTrenchSize = 22/);
});

test('generation is independent of JSON key order', () => {
  const road = '/assets/combat-backdrops-anime-v1/road.png';
  const first = { [backdrop]: { Tank: settings, Infantry: settings }, [road]: settings };
  const second = { [road]: settings, [backdrop]: { Infantry: settings, Tank: settings } };
  assert.equal(render(first, exists), render(second, exists));
  assert.match(render({}, exists), /catalog =\n\[\]/);
});

test('invalid catalogs fail with context instead of generating bad Elm', () => {
  for (const invalid of [null, [], 'invalid']) {
    assert.throws(() => render(invalid, exists), /expected an object/);
  }
  assert.throws(() => render({ '/assets/../plains.png': settings }, exists), /Invalid backdrop path/);
  assert.throws(() => render({ [backdrop]: settings }, () => false), /Backdrop does not exist/);
  assert.throws(() => render({ [backdrop]: { Plane: settings } }, exists), /unknown unit kind Plane/);
  assert.throws(() => render({ [backdrop]: { ...settings, typo: 1 } }, exists), /unknown field typo/);
  for (const invalid of [undefined, null, '82', NaN, Infinity, 99]) {
    assert.throws(() => render({ [backdrop]: { ...settings, frontFooting: invalid } }, exists),
      /plains.png.*frontFooting: expected a number between 55 and 98/);
  }
});
