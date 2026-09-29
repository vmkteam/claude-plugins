#!/usr/bin/env bash
# Go-сервис с незакоммиченной фичей PLF-900 и девятью проблемами: SQL injection, IDOR,
# nil dereference, гонка на map, проглоченная ошибка, устаревший кэш, поиск без лимита,
# нет валидации статуса, нет тестов на новые методы (тест-харнесс в пакете есть — по правилам скилла это major).
set -euo pipefail

git init -q -b devel
git config user.name "Eval"
git config user.email "eval@example.com"

mkdir -p pkg/db pkg/rpc

cat > go.mod <<'EOF'
module ordersrv

go 1.24

require (
	github.com/go-pg/pg/v10 v10.14.0
	github.com/vmkteam/zenrpc/v2 v2.3.3
)
EOF

cat > pkg/db/model.go <<'EOF'
package db

type Order struct {
	tableName struct{} `pg:"orders,alias:t,discard_unknown_columns"`

	ID       int      `pg:"orderId,pk"`
	UserID   int      `pg:"userId,use_zero"`
	Title    string   `pg:"title,use_zero"`
	StatusID int      `pg:"statusId,use_zero"`
	Address  *Address `pg:"address"`
}

type Address struct {
	City   string `json:"city"`
	Street string `json:"street"`
}
EOF

cat > pkg/db/order_repo.go <<'EOF'
package db

import (
	"context"
	"errors"

	"github.com/go-pg/pg/v10"
	"github.com/go-pg/pg/v10/orm"
)

type OpFunc func(query *orm.Query)

func WithColumns(cols ...string) OpFunc {
	return func(q *orm.Query) { q.Column(cols...) }
}

type OrderRepo struct {
	db orm.DB
}

func NewOrderRepo(db orm.DB) OrderRepo { return OrderRepo{db: db} }

// OrderByID returns Order by primary key. Returns nil, nil when not found.
func (r OrderRepo) OrderByID(ctx context.Context, id int, ops ...OpFunc) (*Order, error) {
	o := &Order{ID: id}
	q := r.db.ModelContext(ctx, o).WherePK()
	for _, op := range ops {
		op(q)
	}
	err := q.Select()
	if errors.Is(err, pg.ErrNoRows) {
		return nil, nil
	}
	return o, err
}

// CountOrders returns count of orders for user.
func (r OrderRepo) CountOrders(ctx context.Context, userID int) (int, error) {
	return r.db.ModelContext(ctx, (*Order)(nil)).Where(`"userId" = ?`, userID).Count()
}

// UpdateOrder updates Order columns.
func (r OrderRepo) UpdateOrder(ctx context.Context, o *Order, ops ...OpFunc) (bool, error) {
	q := r.db.ModelContext(ctx, o).WherePK()
	for _, op := range ops {
		op(q)
	}
	res, err := q.Update()
	if err != nil {
		return false, err
	}
	return res.RowsAffected() > 0, nil
}
EOF

cat > pkg/rpc/order.go <<'EOF'
package rpc

import (
	"context"
	"net/http"

	"ordersrv/pkg/db"

	"github.com/vmkteam/zenrpc/v2"
)

var ErrNotFound = zenrpc.NewStringError(http.StatusNotFound, "not found")

func newInternalError(err error) *zenrpc.Error {
	return zenrpc.NewError(http.StatusInternalServerError, err)
}

type OrderService struct {
	zenrpc.Service
	repo db.OrderRepo
}

func NewOrderService(repo db.OrderRepo) *OrderService {
	return &OrderService{repo: repo}
}

// Count returns count of current user orders.
//
//zenrpc:return int
func (s OrderService) Count(ctx context.Context) (int, error) {
	u := UserFromContext(ctx)
	n, err := s.repo.CountOrders(ctx, u.ID)
	if err != nil {
		return 0, newInternalError(err)
	}
	return n, nil
}
EOF

cat > pkg/rpc/auth.go <<'EOF'
package rpc

import "context"

type ctxKey int

const userKey ctxKey = iota

type User struct {
	ID    int
	Login string
}

// UserFromContext returns authenticated user set by auth middleware.
func UserFromContext(ctx context.Context) User {
	u, _ := ctx.Value(userKey).(User)
	return u
}
EOF

cat > pkg/rpc/rpc_test.go <<'EOF'
package rpc

import (
	"context"
	"os"
	"testing"

	"ordersrv/pkg/db"

	"github.com/go-pg/pg/v10"
	"github.com/go-pg/pg/v10/orm"
	"github.com/stretchr/testify/require"
)

var testDB orm.DB

func TestMain(m *testing.M) {
	cfg, err := pg.ParseURL(os.Getenv("DB_CONN"))
	if err != nil {
		cfg, _ = pg.ParseURL("postgresql://localhost:5432/test-ordersrv?sslmode=disable")
	}
	testDB = pg.Connect(cfg)
	os.Exit(m.Run())
}

func withUser(ctx context.Context, userID int) context.Context {
	return context.WithValue(ctx, userKey, User{ID: userID})
}

func TestDBOrderService_Count(t *testing.T) {
	srv := NewOrderService(db.NewOrderRepo(testDB))

	t.Run("user without orders has zero", func(t *testing.T) {
		n, err := srv.Count(withUser(t.Context(), -1))
		require.NoError(t, err)
		require.Zero(t, n)
	})
}
EOF

git add -A
git commit -q -m "Initial ordersrv"
git init -q --bare .origin.git
mkdir -p .git/info && echo ".origin.git/" >> .git/info/exclude
git remote add origin "$PWD/.origin.git"
git push -q origin devel
git fetch -q origin
git branch -q --set-upstream-to=origin/devel devel

# --- Незакоммиченные изменения PLF-900 ---

cat > pkg/db/order_repo_ext.go <<'EOF'
package db

import "context"

// SearchByTitle returns user orders with title containing the given text.
func (r OrderRepo) SearchByTitle(ctx context.Context, userID int, title string) ([]Order, error) {
	var orders []Order
	_, err := r.db.QueryContext(ctx, &orders,
		`SELECT * FROM orders WHERE "userId" = ? AND title ILIKE '%`+title+`%' ORDER BY "orderId" DESC`, userID)
	return orders, err
}
EOF

cat > pkg/rpc/order.go <<'EOF'
package rpc

import (
	"context"
	"net/http"

	"ordersrv/pkg/db"

	"github.com/vmkteam/zenrpc/v2"
)

var ErrNotFound = zenrpc.NewStringError(http.StatusNotFound, "not found")

func newInternalError(err error) *zenrpc.Error {
	return zenrpc.NewError(http.StatusInternalServerError, err)
}

type Order struct {
	ID       int    `json:"orderId"`
	Title    string `json:"title"`
	StatusID int    `json:"statusId"`
	City     string `json:"city"`
}

func NewOrder(in *db.Order) *Order {
	return &Order{
		ID:       in.ID,
		Title:    in.Title,
		StatusID: in.StatusID,
		City:     in.Address.City,
	}
}

type OrderService struct {
	zenrpc.Service
	repo  db.OrderRepo
	cache map[int]*Order
}

func NewOrderService(repo db.OrderRepo) *OrderService {
	return &OrderService{repo: repo, cache: make(map[int]*Order)}
}

// Count returns count of current user orders.
//
//zenrpc:return int
func (s OrderService) Count(ctx context.Context) (int, error) {
	u := UserFromContext(ctx)
	n, err := s.repo.CountOrders(ctx, u.ID)
	if err != nil {
		return 0, newInternalError(err)
	}
	return n, nil
}

// Search returns current user orders by title.
//
//zenrpc:title search text
//zenrpc:return []Order
func (s OrderService) Search(ctx context.Context, title string) ([]Order, error) {
	u := UserFromContext(ctx)
	list, err := s.repo.SearchByTitle(ctx, u.ID, title)
	if err != nil {
		return nil, newInternalError(err)
	}
	res := make([]Order, 0, len(list))
	for i := range list {
		res = append(res, *NewOrder(&list[i]))
	}
	return res, nil
}

// GetByID returns order by id.
//
//zenrpc:orderId order id
//zenrpc:return Order
//zenrpc:404 Not Found
func (s OrderService) GetByID(ctx context.Context, orderId int) (*Order, error) {
	if o, ok := s.cache[orderId]; ok {
		return o, nil
	}
	order, err := s.repo.OrderByID(ctx, orderId)
	if err != nil {
		return nil, newInternalError(err)
	}
	res := NewOrder(order)
	s.cache[orderId] = res
	return res, nil
}

// SetStatus changes order status.
//
//zenrpc:orderId order id
//zenrpc:statusId new status
//zenrpc:return bool
func (s OrderService) SetStatus(ctx context.Context, orderId, statusId int) (bool, error) {
	u := UserFromContext(ctx)
	order, err := s.repo.OrderByID(ctx, orderId)
	if err != nil {
		return false, newInternalError(err)
	} else if order == nil || order.UserID != u.ID {
		return false, ErrNotFound
	}
	order.StatusID = statusId
	ok, _ := s.repo.UpdateOrder(ctx, order, db.WithColumns("statusId"))
	return ok, nil
}
EOF
