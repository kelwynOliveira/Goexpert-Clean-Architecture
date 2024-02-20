docker:
	docker-compose up -d

migrate:
	migrate -path=migrations -database "mysql://root:root@tcp(localhost:3306)/orders?query" -verbose up

migrate-down:
	migrate -path ./migrations -database "mysql://root:root@tcp(localhost:3306)/orders?query" -verbose down

.PHONY: migrate migrate-down docker run