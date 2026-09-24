// Package handlers implementa los endpoints HTTP de la API.
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"cine-api/internal/models"
	"cine-api/internal/repository"
)

var dniRegexp = regexp.MustCompile(`^\d{7,11}$`)

// Handler agrupa los endpoints y sus dependencias.
type Handler struct {
	repo repository.Repository
}

// New crea un Handler.
func New(repo repository.Repository) *Handler {
	return &Handler{repo: repo}
}

// Register registra las rutas en el mux.
//
// El enunciado pide GET /peliculas/{fecha} y GET /peliculas/{IdPelicula}, que
// comparten la misma plantilla de ruta. Se resuelve con una única ruta que
// decide por el formato del parámetro: AAAA-MM-DD es una fecha y un entero es
// un IdPelicula.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /peliculas/{param}", h.Peliculas)
	mux.HandleFunc("POST /reservas", h.CrearReserva)
	mux.HandleFunc("GET /health", h.Health)
}

// Peliculas despacha a Cartelera o a DetallePelicula según el parámetro.
func (h *Handler) Peliculas(w http.ResponseWriter, r *http.Request) {
	param := r.PathValue("param")

	if fecha, err := time.Parse(time.DateOnly, param); err == nil {
		h.cartelera(w, r, fecha)
		return
	}
	if id, err := strconv.Atoi(param); err == nil {
		h.detallePelicula(w, r, id)
		return
	}
	writeError(w, http.StatusBadRequest,
		"el parámetro debe ser una fecha con formato AAAA-MM-DD o un IdPelicula numérico")
}

func (h *Handler) cartelera(w http.ResponseWriter, r *http.Request, fecha time.Time) {
	funciones, err := h.repo.Cartelera(r.Context(), fecha)
	if err != nil {
		internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, funciones)
}

func (h *Handler) detallePelicula(w http.ResponseWriter, r *http.Request, id int) {
	if id <= 0 {
		writeError(w, http.StatusBadRequest, "el IdPelicula debe ser mayor a cero")
		return
	}
	pelicula, err := h.repo.Pelicula(r.Context(), id)
	if errors.Is(err, repository.ErrNotFound) {
		writeError(w, http.StatusNotFound, "la película "+strconv.Itoa(id)+" no existe")
		return
	}
	if err != nil {
		internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, pelicula)
}

// CrearReserva maneja POST /reservas.
func (h *Handler) CrearReserva(w http.ResponseWriter, r *http.Request) {
	var req models.ReservaRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "cuerpo JSON inválido: "+err.Error())
		return
	}
	req.DNI = strings.TrimSpace(req.DNI)

	if msg := validarReserva(req); msg != "" {
		writeJSON(w, http.StatusBadRequest, models.ResultadoReserva{Codigo: models.CodigoDatosInvalidos, Mensaje: msg})
		return
	}

	res, err := h.repo.Reservar(r.Context(), req)
	if err != nil {
		internalError(w, r, err)
		return
	}
	writeJSON(w, statusReserva(res.Codigo), res)
}

func validarReserva(req models.ReservaRequest) string {
	switch {
	case req.IdFuncion <= 0:
		return "idFuncion debe ser mayor a cero"
	case req.Cantidad <= 0:
		return "cantidad debe ser mayor a cero"
	case !dniRegexp.MatchString(req.DNI):
		return "dni debe tener entre 7 y 11 dígitos"
	}
	return ""
}

// statusReserva traduce el código del stored procedure a un status HTTP.
func statusReserva(codigo int) int {
	switch codigo {
	case models.CodigoOK:
		return http.StatusCreated
	case models.CodigoDatosInvalidos:
		return http.StatusBadRequest
	case models.CodigoFuncionInexistente:
		return http.StatusNotFound
	case models.CodigoFuncionNoDisponible, models.CodigoSinButacas:
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

// Health informa si la API y la base de datos están disponibles.
func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := h.repo.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "error", "db": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("no se pudo escribir la respuesta", "error", err)
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, models.ErrorResponse{Mensaje: msg})
}

// internalError registra el detalle y devuelve un mensaje genérico al cliente.
func internalError(w http.ResponseWriter, r *http.Request, err error) {
	slog.Error("error interno", "method", r.Method, "path", r.URL.Path, "error", err)
	writeError(w, http.StatusInternalServerError, "error interno del servidor")
}
