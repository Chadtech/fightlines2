.PHONY: build frontend generate-api combat-theater-calibrations sprites check check-all run dev editor logs

PRODUCTION ?= false
RUST_TEST_ARGS ?=

build: PRODUCTION = true
build: frontend
	cargo build --locked

generate-api:
	cargo run --locked -p fightlines-server -- --export-schema > schema.json.tmp
	mv schema.json.tmp schema.json
	npm run generate-api

sprites:
	npm run build-sprites

combat-theater-calibrations:
	node tools/build-combat-theater-calibrations.cjs

frontend: generate-api combat-theater-calibrations
	node tools/build-config.cjs $(PRODUCTION)
	elm make src/Fightlines.elm --output=public/elm.js
	node tools/build-dev-tools.cjs $(PRODUCTION)

check-all: RUST_TEST_ARGS = --include-ignored
check-all: check

check: combat-theater-calibrations
	cargo fmt --all -- --check
	cargo clippy --locked --all-targets -- -D warnings
	cargo test --locked -- $(RUST_TEST_ARGS)
	elm-format src --validate
	node --test tools/check-combat-theater-calibrations.cjs
	node tools/check-movement.cjs
	node tools/check-shoreline.cjs
	node tools/check-roads.cjs
	node tools/check-turns.cjs
	node tools/check-orders.cjs
	node tools/check-lifecycle.cjs
	node tools/check-replay.cjs
	node tools/check-combat-chart.cjs
	node tools/check-planning.cjs
	node tools/check-pointer.cjs
	node tools/check-local-storage.cjs
	node tools/check-audio.cjs
	node tools/check-home.cjs
	$(MAKE) frontend
	elm make src/DevTools.elm src/Style.elm src/View/*.elm src/Fightlines/View/*.elm src/Game/View/*.elm --output=/dev/null

dev editor logs: PRODUCTION = false

run: frontend
	cargo run --locked -p fightlines-server

dev: frontend
	cargo run --locked -p fightlines-server -- --dev-game --map-editor --game-logs

editor: frontend
	cargo run --locked -p fightlines-server -- --map-editor

logs: frontend
	cargo run --locked -p fightlines-server -- --game-logs
