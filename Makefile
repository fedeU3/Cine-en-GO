.PHONY: up down reset run test build

# Levanta MySQL + API con Docker
up:
	docker compose up --build -d

down:
	docker compose down

# Borra el volumen de la BD para que se vuelvan a ejecutar los scripts de db/
reset:
	docker compose down -v
	docker compose up --build -d

# Corre la API localmente (requiere una BD accesible; ver variables en el README)
run:
	go run ./cmd/api

test:
	go test ./...

build:
	go build -o bin/api ./cmd/api
