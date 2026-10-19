// Comando api levanta el servidor HTTP de la API del cine.
package main

import (
	"context"
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-sql-driver/mysql"

	"cine-api/docs"
	"cine-api/internal/handlers"
	"cine-api/internal/repository"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, nil)))

	if err := run(); err != nil {
		slog.Error("la API terminó con error", "error", err)
		os.Exit(1)
	}
}

func run() error {
	db, err := openDB()
	if err != nil {
		return err
	}
	defer db.Close()

	mux := http.NewServeMux()
	handlers.New(repository.NewMySQL(db)).Register(mux)
	docs.Register(mux)
	mux.Handle("GET /{$}", http.RedirectHandler("/swagger/", http.StatusFound))

	srv := &http.Server{
		Addr:              ":" + getenv("PORT", "8080"),
		Handler:           logRequests(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
	}

	// Apagado ordenado ante SIGINT/SIGTERM.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		slog.Info("API escuchando", "addr", srv.Addr, "swagger", "http://localhost"+srv.Addr+"/swagger/")
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		slog.Info("apagando la API")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
	return nil
}

// openDB abre el pool de conexiones y espera a que MySQL esté disponible
// (útil con docker compose, donde la BD puede tardar en iniciar).
func openDB() (*sql.DB, error) {
	cfg := mysql.NewConfig()
	cfg.User = getenv("DB_USER", "cine")
	cfg.Passwd = getenv("DB_PASSWORD", "cine")
	cfg.Net = "tcp"
	cfg.Addr = getenv("DB_HOST", "127.0.0.1") + ":" + getenv("DB_PORT", "3306")
	cfg.DBName = getenv("DB_NAME", "cine")
	cfg.ParseTime = true
	cfg.Loc = time.Local
	cfg.InterpolateParams = true

	db, err := sql.Open("mysql", cfg.FormatDSN())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	for intento := 1; ; intento++ {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		err = db.PingContext(ctx)
		cancel()
		if err == nil {
			return db, nil
		}
		if intento == 30 {
			db.Close()
			return nil, err
		}
		slog.Warn("esperando a la base de datos", "intento", intento, "error", err)
		time.Sleep(2 * time.Second)
	}
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		slog.Info("request", "method", r.Method, "path", r.URL.Path,
			"status", rec.status, "duration", time.Since(start))
	})
}
