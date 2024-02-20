# Clean Architecture challenge

Goexpert postgraduation project

## Challenge Description

> Hello devs!
> Now it's time to get down to work. For this challenge, you'll need to create a usecase for listing orders.
> This listing needs to be done with:
>
> - Endpoint REST (GET /order)
> - Service ListOrders with GRPC
> - Query ListOrders GraphQL
>   Don't forget to create the necessary migrations and the api.http file with the request to create and list the orders.
>
> To create the database, use Docker (Dockerfile / docker-compose.yaml), so that when you run the docker compose up command everything should go up, preparing the database.
> Include a README.md with the steps to be taken in the challenge and the port on which the application should respond for each service.

## How to execute

Start docker with `make docker`.

Run the migrations: `make migrate`

Start system: open cmd on `./cmd/ordersystem/` and run `go run main.go wire_gen.go`.

Services:

- GrapgQL: 8080
- gRPC: 50051
- API: 8000 (/order, /orders)

## Challenge Solution Development

Implementation of the `SelectAll` interface inside `internal/entity/interface.go`:

```go
package entity

type OrderRepositoryInterface interface {
	Save(order *Order) error
	// GetTotal() (int, error)
	SelectAll() ([]*Order, error)
}
```

Implementation of the `SelectAll` method inside `internal/infra/database/order_repository.go`:

```go
func (r *OrderRepository) SelectAll() ([]*entity.Order, error) {
	tableRows, err := r.Db.Query("SELECT id, price, tax, final_price FROM orders")
	if err != nil {
		return nil, err
	}

	defer tableRows.Close()

	orders := make([]*entity.Order, 0)

	for tableRows.Next() {
		order := new(entity.Order)
		if err := tableRows.Scan(&order.ID, &order.Price, &order.Tax, &order.FinalPrice); err != nil {
			return nil, err
		}

		orders = append(orders, order)
	}

	if err = tableRows.Err(); err != nil {
		return nil, err
	}

	return orders, nil
}
```

Creation of the usecase `list_orders.go` inside folder `internal/usecase`:

```go
package usecase

import (
	"github.com/kelwynOliveira/Goexpert-Clean-Architecture/internal/entity"
)

type ListOrdersUseCase struct {
	OrderRepository entity.OrderRepositoryInterface
}

func NewListOrdersUseCase(
	OrderRepository entity.OrderRepositoryInterface,
) *ListOrdersUseCase {
	return &ListOrdersUseCase{
		OrderRepository: OrderRepository,
	}
}

func (c *ListOrdersUseCase) Execute() ([]OrderOutputDTO, error) {
	orders, err := c.OrderRepository.SelectAll()
	if err != nil {
		return nil, err
	}

	var dtos []OrderOutputDTO
	for _, order := range orders {
		dto := OrderOutputDTO{
			ID:         order.ID,
			Price:      order.Price,
			Tax:        order.Tax,
			FinalPrice: order.FinalPrice,
		}
		dtos = append(dtos, dto)
	}

	return dtos, nil
}
```

Implementation of the method to list all itens. File `internal/infra/web/order_handler.go`:

```go
func (h *WebOrderHandler) ListAll(w http.ResponseWriter, r *http.Request) {
	listOrders := usecase.NewListOrdersUseCase(h.OrderRepository)

	output, err := listOrders.Execute()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if err = json.NewEncoder(w).Encode(output); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
}
```

gRPC configuration. Added inside file `internal/grpc/protofiles/order.proto`:

```
message Blank {}

message ListOrdersResponse {
  repeated CreateOrderResponse orders = 1;
}

service OrderService {
  rpc CreateOrder(CreateOrderRequest) returns (CreateOrderResponse);
  rpc ListOrders(Blank) returns (ListOrdersResponse);
}
```

With cmd on folder `internal/infra/grpc` run: `protoc --go_out=. --go-grpc_out=. protofiles/order.proto`

Update `internal/grpc/service/order_service.go`:

```go
func NewOrderService(createOrderUseCase usecase.CreateOrderUseCase, listOrdersUseCase usecase.ListOrdersUseCase) *OrderService {
	return &OrderService{
		CreateOrderUseCase: createOrderUseCase,
		ListOrdersUseCase:  listOrdersUseCase,
	}
}

func (s *OrderService) ListOrders(ctx context.Context, in *pb.Blank) (*pb.ListOrdersResponse, error) {
	output, err := s.ListOrdersUseCase.Execute()
	if err != nil {
		return nil, err
	}

	var orders []*pb.CreateOrderResponse
	for _, o := range output {
		orders = append(orders, &pb.CreateOrderResponse{
			Id:         o.ID,
			Price:      float32(o.Price),
			Tax:        float32(o.Tax),
			FinalPrice: float32(o.FinalPrice),
		})
	}

	return &pb.ListOrdersResponse{
		Orders: orders,
	}, nil
}
```

Update graphQL Schema. File `internal/infra/graph/schema.graphqls` added:

```
type Query {
  orders: [Order]!
}
```

Update graphQL resolver. `internal/infra/graph/resolver.go`:

```go
type Resolver struct {
	CreateOrderUseCase usecase.CreateOrderUseCase
	ListOrdersUseCase  usecase.ListOrdersUseCase
}
```

With cmd on folder `internal/infra/graph` run: `go run github.com/99designs/gqlgen generate`

Added method Orders to `internal/infra/graph/schema.resolvers.go`:

```go
func (r *queryResolver) Orders(ctx context.Context) ([]*model.Order, error) {
	output, err := r.ListOrdersUseCase.Execute()
	if err != nil {
		return nil, err
	}

	var orders []*model.Order
	for _, o := range output {
		orders = append(orders, &model.Order{
			ID:         o.ID,
			Price:      float64(o.Price),
			Tax:        float64(o.Tax),
			FinalPrice: float64(o.FinalPrice),
		})
	}

	return orders, nil
}
```

Added function `NewListOrdersUseCase` to `cmd/ordersystem/wire.go`:

```go
func NewListOrdersUseCase(db *sql.DB) *usecase.ListOrdersUseCase {
	wire.Build(
		setOrderRepositoryDependency,
		usecase.NewListOrdersUseCase,
	)
	return &usecase.ListOrdersUseCase{}
}
```

With cmd on folder `cmd/ordersystem/` run: `wire` to update `wire_gen.go`

Update `main.go`:

```go
func main() {
	configs, err := configs.LoadConfig(".")
	if err != nil {
		panic(err)
	}

	db, err := sql.Open(configs.DBDriver, fmt.Sprintf("%s:%s@tcp(%s:%s)/%s", configs.DBUser, configs.DBPassword, configs.DBHost, configs.DBPort, configs.DBName))
	if err != nil {
		panic(err)
	}
	defer db.Close()

	rabbitMQChannel := getRabbitMQChannel()

	eventDispatcher := events.NewEventDispatcher()
	eventDispatcher.Register("OrderCreated", &handler.OrderCreatedHandler{
		RabbitMQChannel: rabbitMQChannel,
	})

	createOrderUseCase := NewCreateOrderUseCase(db, eventDispatcher)
	listOrdersUseCase := NewListOrdersUseCase(db) // Added (wire)

	webserver := webserver.NewWebServer(configs.WebServerPort)
	webOrderHandler := NewWebOrderHandler(db, eventDispatcher)

	webserver.AddHandler("/order", webOrderHandler.Create)
	webserver.AddHandler("/orders", webOrderHandler.ListAll) // Added

	fmt.Println("Starting web server on port", configs.WebServerPort)
	go webserver.Start()

	grpcServer := grpc.NewServer()
	createOrderService := service.NewOrderService(*createOrderUseCase, *listOrdersUseCase) // Updated with list order
	pb.RegisterOrderServiceServer(grpcServer, createOrderService)
	reflection.Register(grpcServer)

	fmt.Println("Starting gRPC server on port", configs.GRPCServerPort)
	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", configs.GRPCServerPort))
	if err != nil {
		panic(err)
	}
	go grpcServer.Serve(lis)

	srv := graphql_handler.NewDefaultServer(graph.NewExecutableSchema(graph.Config{Resolvers: &graph.Resolver{
		CreateOrderUseCase: *createOrderUseCase,
		ListOrdersUseCase:  *listOrdersUseCase, // Added
	}}))
	http.Handle("/", playground.Handler("GraphQL playground", "/query"))
	http.Handle("/query", srv)

	fmt.Println("Starting GraphQL server on port", configs.GraphQLServerPort)
	http.ListenAndServe(":"+configs.GraphQLServerPort, nil)
}
```

Added API `list_orders.http`:

```
GET http://localhost:8000/orders HTTP/1.1
Host: localhost:8000
Accept: application/json
```

Migrations:

run `migrate create -ext=sql -dir=migrations -seq init` to create the migrations.

It will create the folder `migrations` with two sql files.

On `migrations/000001_init.up.sql`:

```sql
CREATE TABLE orders (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    price DECIMAL(10, 2) NOT NULL,
    tax DECIMAL(10, 2) NOT NULL,
    final_price DECIMAL(10, 2) NOT NULL
);

```

On `migrations/000001_init.down.sql`:

```SQL
DROP TABLE IF EXISTS orders
```

To do the migration run: `migrate -path=migrations -database "mysql://root:root@tcp(localhost:3306)/orders?query" -verbose up`

Makefile:

```makefile
docker:
	docker-compose up -d

migrate:
	migrate -path=migrations -database "mysql://root:root@tcp(localhost:3306)/orders?query" -verbose up

migrate-down:
	migrate -path ./migrations -database "mysql://root:root@tcp(localhost:3306)/orders?query" -verbose down

.PHONY: migrate migrate-down docker run
```
