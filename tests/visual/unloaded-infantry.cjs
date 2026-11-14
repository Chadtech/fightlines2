const { expect, graphql, snapshot } = require('./helpers.cjs');

const units = 'scenario { units { id playerNumber location { ... on OnMap { position { x y } } ... on Aboard { carrierId } } } }';
const submitTurn = `mutation($id: String!, $turn: Int!, $orders: [UnitOrderInput!]!) {
  submitTurn(id: $id, turnNumber: $turn, orders: $orders) { turnNumber submitted }
}`;

async function board(session, id) {
  const { game } = await graphql(session, `query($id: String!) { game(id: $id) { turnNumber ${units} } }`, { id });
  return game;
}

function holds(game, side) {
  return game.scenario.units.filter(unit => unit.playerNumber === side)
    .map(unit => ({ unitId: unit.id, path: [unit.location.position] }));
}

async function startWithLoadedTruck(page, peer) {
  const { createLobby: { id } } = await graphql(page,
    'mutation { createLobby(name: "commander", lobbyName: "transport patrol") { id } }');
  const lobby = JSON.stringify(id);
  await graphql(page, `mutation { setLobbySide(id: ${lobby}, playerNumber: PLAYER1) { id } }`);
  await graphql(peer, `mutation { joinLobby(id: ${lobby}, name: "peer") { id } }`);
  await graphql(page, `mutation { startGame(id: ${lobby}) { id } }`);

  const hostOrders = holds(await board(page, id), 'PLAYER1');
  // Board both infantry on the first turn of the frozen visual map.
  hostOrders.find(order => order.unitId === '1').path.push({ x: 2, y: 7 });
  hostOrders.find(order => order.unitId === '2').path.push({ x: 2, y: 8 }, { x: 2, y: 7 });
  await graphql(page, submitTurn, { id, turn: 1, orders: hostOrders });
  const peerOrders = holds(await board(peer, id), 'PLAYER2');
  await graphql(peer, submitTurn, { id, turn: 1, orders: peerOrders });

  const game = await board(page, id);
  expect(game.turnNumber).toBe(2);
  expect(game.scenario.units.filter(unit => unit.location.carrierId === '4').map(unit => unit.id))
    .toEqual(['1', '2']);
  await page.goto(`/game/${id}`);
  return { id, peerOrders };
}

async function checkUnloadedInfantry({ page, browser, baseURL, hasTouch }) {
  const peer = await browser.newContext({ baseURL });
  try {
    const { id, peerOrders } = await startWithLoadedTruck(page, peer);
    const battlefield = page.getByRole('group', { name: 'battlefield', exact: true });
    const orders = page.getByRole('region', { name: 'unit orders', exact: true });
    const picker = page.getByRole('dialog', { name: 'order unloaded infantry', exact: true });
    const move = orders.getByRole('button', { name: /^move( \(m\))?$/ });
    const holdRemaining = { name: 'hold remaining infantry', exact: true };
    const cancelTruck = { name: 'cancel truck order', exact: true };
    const unloads = battlefield.locator('[data-planned-unloads="2"]');
    const infantryRoute = battlefield.locator('polyline[stroke-dasharray="2 1"][points="24,136 8,136"]');

    const activate = element => hasTouch ? element.tap() : element.click();
    const tile = async (x, y) => {
      const bounds = await battlefield.boundingBox();
      const screenX = bounds.x + (x + 0.5) * bounds.width / 17;
      const screenY = bounds.y + (y + 0.5) * bounds.height / 17;
      if (hasTouch) await page.touchscreen.tap(screenX, screenY);
      else await page.mouse.click(screenX, screenY);
    };
    const chooseExits = async () => {
      await activate(battlefield.getByRole('button', { name: /truck 4, cargo: 2/ }));
      await activate(move);
      await tile(1, 7);
      const unload = page.getByRole('dialog', { name: 'unload', exact: true });
      const passengers = unload.getByRole('checkbox');
      await expect(passengers).toHaveCount(2);
      await activate(passengers.nth(0));
      await activate(passengers.nth(1));
      await activate(unload.getByRole('button', { name: 'choose unload squares', exact: true }));
      await expect(unload).toBeHidden();
      await tile(2, 7);
      await expect(picker).toBeHidden();
      await tile(1, 8);
      await expect(picker).toBeVisible();
    };

    await chooseExits();
    await expect(picker.getByText(
      'these infantry can move or attack after unloading from this truck. choose one to order next.',
      { exact: true },
    )).toBeVisible();
    await expect(picker.getByRole('button', { name: /^infantry [12]$/ })).toHaveCount(2);
    await expect(picker.getByRole('button', holdRemaining)).toBeInViewport({ ratio: 1 });
    await expect(picker.getByRole('button', cancelTruck)).toBeInViewport({ ratio: 1 });
    await snapshot(page, 'order-unloaded-infantry');

    await activate(picker.getByRole('button', { name: 'infantry 2', exact: true }));
    await expect(picker).toBeHidden();
    await expect(move).toBeFocused();
    await activate(move);
    await tile(0, 8);
    await expect(infantryRoute).toHaveCount(1);
    await expect(picker).toBeHidden();
    const progress = page.getByText('unloaded infantry · 2 of 2', { exact: true });
    if (hasTouch) await expect(progress).toBeVisible();
    else await expect(orders.getByText('orders', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', holdRemaining)).toHaveCount(0);
    await snapshot(page, 'remaining-infantry-orders');

    const cancelOrder = hasTouch
      ? page.getByRole('button', { name: 'cancel order', exact: true })
      : orders.getByRole('button', { name: 'cancel (esc)', exact: true });
    await activate(cancelOrder);
    await expect(unloads).toHaveCount(0);
    await expect(infantryRoute).toHaveCount(0);

    await page.reload();
    await chooseExits();
    await activate(picker.getByRole('button', holdRemaining));
    await expect(picker).toBeHidden();
    await expect(unloads).toHaveCount(1);
    await activate(page.getByRole('button', { name: 'revoke order', exact: true }));
    await expect(unloads).toHaveCount(0);

    await chooseExits();
    await activate(picker.getByRole('button', { name: 'infantry 2', exact: true }));
    await activate(move);
    await tile(0, 8);
    await activate(orders.getByRole('button', { name: /^hold position( \(h\))?$/ }));
    await expect(unloads).toHaveCount(1);
    await expect(infantryRoute).toHaveCount(1);
    await activate(page.getByRole('button', { name: 'submit turn', exact: true }));
    const warning = page.getByRole('dialog', { name: 'units without orders' });
    const missing = warning.getByRole('list', { name: 'units that will hold position' });
    await expect(missing.getByRole('listitem')).toHaveCount(5);
    const submitted = page.waitForResponse(response =>
      /\bsubmitTurn\s*\(/.test(response.request().postDataJSON()?.query ?? ''));
    await activate(warning.getByRole('button', { name: 'submit anyway', exact: true }));
    const result = await (await submitted).json();
    expect(result.errors).toBeUndefined();
    expect(result.data.submitTurn.submitted).toBe(true);
    await graphql(peer, submitTurn, { id, turn: 2, orders: peerOrders });

    const game = await board(page, id);
    expect(game.turnNumber).toBe(3);
    const position = id => game.scenario.units.find(unit => unit.id === id).location.position;
    expect(position('4')).toEqual({ x: 1, y: 7 });
    expect(position('1')).toEqual({ x: 2, y: 7 });
    expect(position('2')).toEqual({ x: 0, y: 8 });
  } finally {
    await peer.close();
  }
}

module.exports = { checkUnloadedInfantry };
