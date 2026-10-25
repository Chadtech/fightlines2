.PHONY: build frontend generate-api sprites check run dev editor logs

PRODUCTION ?= false

build: PRODUCTION = true
build: frontend
	cargo build --locked

generate-api:
	cargo run --locked -p fightlines-server -- --export-schema > schema.json.tmp
	mv schema.json.tmp schema.json
	npm run generate-api

sprites:
	npm run build-sprites

frontend: generate-api
	node tools/build-config.cjs $(PRODUCTION)
	elm make src/Main.elm --output=public/elm.js
	node tools/build-dev-tools.cjs $(PRODUCTION)

check:
	cargo fmt --all -- --check
	cargo clippy --locked --all-targets -- -D warnings
	cargo test --locked
	elm-format src --validate
	node tools/check-movement.cjs
	node tools/check-shoreline.cjs
	node tools/check-roads.cjs
	node tools/check-turns.cjs
	node tools/check-orders.cjs
	node tools/check-lifecycle.cjs
	node tools/check-replay.cjs
	node tools/check-planning.cjs
	node tools/check-pointer.cjs
	node tools/check-local-storage.cjs
	node tools/check-home.cjs
	$(MAKE) frontend
	elm make src/DevTools.elm src/Style.elm src/View/*.elm src/Game/View/*.elm --output=/dev/null

dev editor logs: PRODUCTION = false

run: frontend
	cargo run --locked -p fightlines-server

dev: frontend
	cargo run --locked -p fightlines-server -- --dev-game --map-editor --game-logs

editor: frontend
	cargo run --locked -p fightlines-server -- --map-editor

logs: frontend
	cargo run --locked -p fightlines-server -- --game-logs
