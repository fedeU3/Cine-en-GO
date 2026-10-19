// Package models contiene las estructuras que expone la API.
package models

import "time"

// FuncionCartelera es una función que se proyecta en una fecha dada.
type FuncionCartelera struct {
	IdFuncion          int     `json:"idFuncion"`
	IdPelicula         int     `json:"idPelicula"`
	IdSala             int     `json:"idSala"`
	Pelicula           string  `json:"pelicula"`
	Sala               string  `json:"sala"`
	HoraInicio         string  `json:"horaInicio"`
	Precio             float64 `json:"precio"`
	ButacasDisponibles int     `json:"butacasDisponibles"`
}

// Genero de una película.
type Genero struct {
	IdGenero int    `json:"idGenero"`
	Genero   string `json:"genero"`
}

// Pelicula con sus datos relevantes y sus próximas funciones.
type Pelicula struct {
	IdPelicula        int               `json:"idPelicula"`
	Pelicula          string            `json:"pelicula"`
	Sinopsis          string            `json:"sinopsis"`
	Duracion          int               `json:"duracion"`
	Actores           string            `json:"actores"`
	Genero            Genero            `json:"genero"`
	Estado            string            `json:"estado"`
	Observaciones     *string           `json:"observaciones"`
	ProximasFunciones []FuncionPelicula `json:"proximasFunciones"`
}

// FuncionPelicula es una próxima función de una película.
type FuncionPelicula struct {
	IdFuncion           int       `json:"idFuncion"`
	IdSala              int       `json:"idSala"`
	Sala                string    `json:"sala"`
	FechaProbableInicio time.Time `json:"fechaProbableInicio"`
	FechaProbableFin    time.Time `json:"fechaProbableFin"`
	Precio              float64   `json:"precio"`
}

// ReservaRequest es el cuerpo de POST /reservas.
type ReservaRequest struct {
	IdFuncion int    `json:"idFuncion"`
	Cantidad  int    `json:"cantidad"`
	DNI       string `json:"dni"`
}

// Códigos que devuelve sp_ReservarFuncion.
const (
	CodigoOK                  = 0
	CodigoDatosInvalidos      = 1
	CodigoFuncionInexistente  = 2
	CodigoFuncionNoDisponible = 3
	CodigoSinButacas          = 4
	CodigoErrorInesperado     = 99
)

// ResultadoReserva es la respuesta de sp_ReservarFuncion y de POST /reservas.
type ResultadoReserva struct {
	Codigo   int               `json:"codigo"`
	Mensaje  string            `json:"mensaje"`
	Reservas []ButacaReservada `json:"reservas,omitempty"`
}

// ButacaReservada es una reserva generada (una por butaca).
type ButacaReservada struct {
	IdReserva int64 `json:"idReserva"`
	IdButaca  int   `json:"idButaca"`
	NroButaca int   `json:"nroButaca"`
	Fila      int   `json:"fila"`
	Columna   int   `json:"columna"`
}

// ErrorResponse es el cuerpo de las respuestas de error.
type ErrorResponse struct {
	Mensaje string `json:"mensaje"`
}
