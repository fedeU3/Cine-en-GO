package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cine-api/internal/models"
	"cine-api/internal/repository"
)

type fakeRepo struct {
	fechaConsultada time.Time
	reservaRecibida *models.ReservaRequest
	resultado       *models.ResultadoReserva
	err             error
}

func (f *fakeRepo) Cartelera(_ context.Context, fecha time.Time) ([]models.FuncionCartelera, error) {
	f.fechaConsultada = fecha
	return []models.FuncionCartelera{{IdFuncion: 1, IdPelicula: 1, IdSala: 1, Pelicula: "Interestelar"}}, f.err
}

func (f *fakeRepo) Pelicula(_ context.Context, id int) (*models.Pelicula, error) {
	if f.err != nil {
		return nil, f.err
	}
	if id != 1 {
		return nil, repository.ErrNotFound
	}
	return &models.Pelicula{IdPelicula: 1, Pelicula: "Interestelar"}, nil
}

func (f *fakeRepo) Reservar(_ context.Context, req models.ReservaRequest) (*models.ResultadoReserva, error) {
	f.reservaRecibida = &req
	return f.resultado, f.err
}

func (f *fakeRepo) Ping(context.Context) error { return f.err }

func serve(repo *fakeRepo, method, path, body string) *httptest.ResponseRecorder {
	mux := http.NewServeMux()
	New(repo).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(body)))
	return rec
}

func TestPeliculas_Cartelera(t *testing.T) {
	repo := &fakeRepo{}
	rec := serve(repo, http.MethodGet, "/peliculas/2026-09-23", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	if got := repo.fechaConsultada.Format(time.DateOnly); got != "2026-09-23" {
		t.Errorf("fecha consultada = %s", got)
	}
	var funciones []models.FuncionCartelera
	if err := json.Unmarshal(rec.Body.Bytes(), &funciones); err != nil || len(funciones) != 1 {
		t.Errorf("respuesta inesperada: %s", rec.Body)
	}
}

func TestPeliculas_Detalle(t *testing.T) {
	tests := []struct {
		name   string
		path   string
		err    error
		status int
	}{
		{"existe", "/peliculas/1", nil, http.StatusOK},
		{"no existe", "/peliculas/99", nil, http.StatusNotFound},
		{"id cero", "/peliculas/0", nil, http.StatusBadRequest},
		{"parámetro inválido", "/peliculas/abc", nil, http.StatusBadRequest},
		{"fecha inválida", "/peliculas/2026-13-45", nil, http.StatusBadRequest},
		{"error de BD", "/peliculas/1", errors.New("boom"), http.StatusInternalServerError},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := serve(&fakeRepo{err: tt.err}, http.MethodGet, tt.path, "")
			if rec.Code != tt.status {
				t.Errorf("status = %d, want %d (body %s)", rec.Code, tt.status, rec.Body)
			}
		})
	}
}

func TestCrearReserva_Validaciones(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"json inválido", `{`},
		{"campo desconocido", `{"idFuncion":1,"cantidad":1,"dni":"30123456","x":1}`},
		{"sin función", `{"cantidad":1,"dni":"30123456"}`},
		{"cantidad cero", `{"idFuncion":1,"cantidad":0,"dni":"30123456"}`},
		{"dni inválido", `{"idFuncion":1,"cantidad":1,"dni":"12ab"}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeRepo{}
			rec := serve(repo, http.MethodPost, "/reservas", tt.body)
			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want 400 (body %s)", rec.Code, rec.Body)
			}
			if repo.reservaRecibida != nil {
				t.Error("no debería llamar al repositorio con datos inválidos")
			}
		})
	}
}

func TestCrearReserva_CodigosDelSP(t *testing.T) {
	tests := []struct {
		codigo int
		status int
	}{
		{models.CodigoOK, http.StatusCreated},
		{models.CodigoDatosInvalidos, http.StatusBadRequest},
		{models.CodigoFuncionInexistente, http.StatusNotFound},
		{models.CodigoFuncionNoDisponible, http.StatusConflict},
		{models.CodigoSinButacas, http.StatusConflict},
		{models.CodigoErrorInesperado, http.StatusInternalServerError},
	}
	for _, tt := range tests {
		repo := &fakeRepo{resultado: &models.ResultadoReserva{Codigo: tt.codigo, Mensaje: "msg"}}
		rec := serve(repo, http.MethodPost, "/reservas", `{"idFuncion":3,"cantidad":2,"dni":" 30123456 "}`)
		if rec.Code != tt.status {
			t.Errorf("codigo %d: status = %d, want %d", tt.codigo, rec.Code, tt.status)
		}
		if repo.reservaRecibida.DNI != "30123456" {
			t.Errorf("el DNI debería llegar sin espacios, llegó %q", repo.reservaRecibida.DNI)
		}
	}
}
