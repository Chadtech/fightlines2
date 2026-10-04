.PHONY: build frontend generate-api check run

build: frontend
	cargo build --locked

generate-api:
	cargo run --locked -p fightlines-server -- --export-schema > schema.json.tmp
	mv schema.json.tmp schema.json
	npm run generate-api

frontend: generate-api
	elm make src/Main.elm --output=public/elm.js

check:
	cargo fmt --all -- --check
	cargo clippy --locked --all-targets -- -D warnings
	cargo test --locked
	elm-format src --validate
	$(MAKE) frontend
	elm make src/Style.elm src/View/*.elm --output=/dev/null

run: frontend
	cargo run --locked -p fightlines-server
