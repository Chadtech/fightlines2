.PHONY: build frontend generate-api sprites check run dev

build: frontend
	cargo build --locked

generate-api:
	cargo run --locked -p fightlines-server -- --export-schema > schema.json.tmp
	mv schema.json.tmp schema.json
	npm run generate-api

sprites:
	npm run build-sprites

frontend: generate-api
	elm make src/Main.elm --output=public/elm.js

check:
	cargo fmt --all -- --check
	cargo clippy --locked --all-targets -- -D warnings
	cargo test --locked
	elm-format src --validate
	node tools/check-movement.cjs
	node tools/check-turns.cjs
	$(MAKE) frontend
	elm make src/Style.elm src/View/*.elm --output=/dev/null

run: frontend
	cargo run --locked -p fightlines-server

dev: frontend
	cargo run --locked -p fightlines-server -- --dev-game
