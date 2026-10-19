// Package repository accede a la base de datos a través de los stored procedures.
package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"cine-api/internal/models"
)

// ErrNotFound indica que el recurso buscado no existe.
var ErrNotFound = errors.New("recurso no encontrado")

// Repository define las operaciones que la API necesita de la base de datos.
// Los handlers dependen de esta interfaz, lo que permite testearlos sin BD.
type Repository interface {
	Cartelera(ctx context.Context, fecha time.Time) ([]models.FuncionCartelera, error)
	Pelicula(ctx context.Context, idPelicula int) (*models.Pelicula, error)
	Reservar(ctx context.Context, req models.ReservaRequest) (*models.ResultadoReserva, error)
	Ping(ctx context.Context) error
}

// MySQLRepository implementa Repository sobre MySQL.
type MySQLRepository struct {
	db *sql.DB
}

// NewMySQL crea un repositorio a partir de una conexión abierta.
func NewMySQL(db *sql.DB) *MySQLRepository {
	return &MySQLRepository{db: db}
}

// Ping verifica la conexión con la base de datos.
func (r *MySQLRepository) Ping(ctx context.Context) error {
	return r.db.PingContext(ctx)
}

// Cartelera ejecuta sp_PeliculasEnCartelera.
func (r *MySQLRepository) Cartelera(ctx context.Context, fecha time.Time) ([]models.FuncionCartelera, error) {
	rows, err := r.db.QueryContext(ctx, "CALL sp_PeliculasEnCartelera(?)", fecha.Format(time.DateOnly))
	if err != nil {
		return nil, fmt.Errorf("sp_PeliculasEnCartelera: %w", err)
	}
	defer rows.Close()

	funciones := []models.FuncionCartelera{}
	for rows.Next() {
		var f models.FuncionCartelera
		if err := rows.Scan(&f.IdFuncion, &f.IdPelicula, &f.IdSala, &f.Pelicula, &f.Sala,
			&f.HoraInicio, &f.Precio, &f.ButacasDisponibles); err != nil {
			return nil, fmt.Errorf("sp_PeliculasEnCartelera: %w", err)
		}
		funciones = append(funciones, f)
	}
	return funciones, rows.Err()
}

// Pelicula ejecuta sp_ConsultarPelicula, que devuelve dos result sets:
// los datos de la película y sus próximas funciones.
func (r *MySQLRepository) Pelicula(ctx context.Context, idPelicula int) (*models.Pelicula, error) {
	rows, err := r.db.QueryContext(ctx, "CALL sp_ConsultarPelicula(?)", idPelicula)
	if err != nil {
		return nil, fmt.Errorf("sp_ConsultarPelicula: %w", err)
	}
	defer rows.Close()

	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("sp_ConsultarPelicula: %w", err)
		}
		return nil, ErrNotFound
	}

	p := models.Pelicula{ProximasFunciones: []models.FuncionPelicula{}}
	if err := rows.Scan(&p.IdPelicula, &p.Pelicula, &p.Sinopsis, &p.Duracion, &p.Actores,
		&p.Genero.IdGenero, &p.Genero.Genero, &p.Estado, &p.Observaciones); err != nil {
		return nil, fmt.Errorf("sp_ConsultarPelicula: %w", err)
	}

	if rows.NextResultSet() {
		for rows.Next() {
			var f models.FuncionPelicula
			if err := rows.Scan(&f.IdFuncion, &f.IdSala, &f.Sala,
				&f.FechaProbableInicio, &f.FechaProbableFin, &f.Precio); err != nil {
				return nil, fmt.Errorf("sp_ConsultarPelicula: %w", err)
			}
			p.ProximasFunciones = append(p.ProximasFunciones, f)
		}
	}
	return &p, rows.Err()
}

// Reservar ejecuta sp_ReservarFuncion. El primer result set trae Codigo y
// Mensaje; si la reserva fue exitosa, el segundo trae las butacas asignadas.
// Los errores de negocio se informan en el resultado, no como error de Go.
func (r *MySQLRepository) Reservar(ctx context.Context, req models.ReservaRequest) (*models.ResultadoReserva, error) {
	rows, err := r.db.QueryContext(ctx, "CALL sp_ReservarFuncion(?, ?, ?)", req.IdFuncion, req.Cantidad, req.DNI)
	if err != nil {
		return nil, fmt.Errorf("sp_ReservarFuncion: %w", err)
	}
	defer rows.Close()

	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return nil, fmt.Errorf("sp_ReservarFuncion: %w", err)
		}
		return nil, errors.New("sp_ReservarFuncion: no devolvió resultado")
	}

	var res models.ResultadoReserva
	if err := rows.Scan(&res.Codigo, &res.Mensaje); err != nil {
		return nil, fmt.Errorf("sp_ReservarFuncion: %w", err)
	}

	if res.Codigo == models.CodigoOK && rows.NextResultSet() {
		for rows.Next() {
			var b models.ButacaReservada
			if err := rows.Scan(&b.IdReserva, &b.IdButaca, &b.NroButaca, &b.Fila, &b.Columna); err != nil {
				return nil, fmt.Errorf("sp_ReservarFuncion: %w", err)
			}
			res.Reservas = append(res.Reservas, b)
		}
	}
	return &res, rows.Err()
}
