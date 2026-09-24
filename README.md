# Cine API — Examen de ingreso Backend Junior (Onebittech)

Base de datos para una sala de cine y API REST en **Go** para consultar la cartelera, ver los datos de una película y reservar entradas.

- **Base de datos:** MySQL 8.4 (tablas, restricciones y stored procedures en [`db/`](db/))
- **API:** Go 1.24, solo con la biblioteca estándar (`net/http`) y el driver `go-sql-driver/mysql`
- **Documentación:** Swagger UI con especificación OpenAPI 3 ([`docs/openapi.yaml`](docs/openapi.yaml))

---

## Cómo ejecutarlo

### Opción 1: Docker (recomendada)

Requisitos: Docker con Docker Compose.

```bash
docker compose up --build -d      # o: make up
```

Esto levanta:

| Servicio | URL / puerto | Descripción |
|---|---|---|
| `api` | http://localhost:8080 | API REST |
| Swagger UI | http://localhost:8080/swagger/ | Documentación interactiva |
| `db` | `localhost:3306` (usuario `cine` / clave `cine`) | MySQL con datos de prueba |

La primera vez que se crea el volumen, MySQL ejecuta en orden los scripts de `db/`:

1. `01_schema.sql`: tablas y restricciones
2. `02_procedures.sql`: stored procedures
3. `03_seed.sql`: datos de prueba. Las funciones se crean **relativas a la fecha actual** (hoy, mañana y pasado mañana), así que siempre hay cartelera.

Para volver a crear la base desde cero: `make reset` (equivale a `docker compose down -v && docker compose up --build -d`).

### Opción 2: sin Docker

1. Tener un MySQL 8.0.16+ (hacen falta los `CHECK`) y ejecutar los scripts:
   ```bash
   mysql -uroot -p < db/01_schema.sql
   mysql -uroot -p < db/02_procedures.sql
   mysql -uroot -p < db/03_seed.sql
   ```
2. Levantar la API (Go 1.24+):
   ```bash
   DB_HOST=127.0.0.1 DB_PORT=3306 DB_USER=root DB_PASSWORD=secret go run ./cmd/api
   ```

Variables de entorno (entre paréntesis, el valor por defecto): `DB_HOST` (`127.0.0.1`), `DB_PORT` (`3306`), `DB_USER` (`cine`), `DB_PASSWORD` (`cine`), `DB_NAME` (`cine`), `PORT` (`8080`).

### Tests

```bash
go test ./...     # o: make test
```

---

## Endpoints

| Método | Ruta | Descripción | Stored procedure |
|---|---|---|---|
| GET | `/peliculas/{fecha}` | Películas en cartelera en la fecha (`AAAA-MM-DD`) | `sp_PeliculasEnCartelera` |
| GET | `/peliculas/{idPelicula}` | Datos de una película y sus próximas funciones | `sp_ConsultarPelicula` |
| POST | `/reservas` | Reserva de entradas para una función | `sp_ReservarFuncion` |
| GET | `/health` | Estado de la API y de la conexión a la BD | — |
| GET | `/swagger/` | Swagger UI | — |

### Ejemplos

```bash
# Cartelera de mañana (macOS: date -v+1d +%F  |  Linux: date -d tomorrow +%F)
curl http://localhost:8080/peliculas/$(date -v+1d +%F)
```
```json
[
  {"idFuncion":5,"idPelicula":3,"idSala":2,"pelicula":"Intensa-Mente","sala":"Sala 2 3D","horaInicio":"16:00:00","precio":4800,"butacasDisponibles":10},
  {"idFuncion":3,"idPelicula":1,"idSala":1,"pelicula":"Interestelar","sala":"Sala 1","horaInicio":"18:00:00","precio":5500,"butacasDisponibles":39}
]
```

```bash
# Datos de una película
curl http://localhost:8080/peliculas/1
```
```json
{
  "idPelicula": 1, "pelicula": "Interestelar", "sinopsis": "...", "duracion": 169,
  "actores": "Matthew McConaughey, Anne Hathaway, Jessica Chastain",
  "genero": {"idGenero": 4, "genero": "Ciencia Ficción"},
  "estado": "A", "observaciones": null,
  "proximasFunciones": [
    {"idFuncion": 3, "idSala": 1, "sala": "Sala 1", "fechaProbableInicio": "2026-09-23T18:00:00-03:00", "fechaProbableFin": "2026-09-23T21:00:00-03:00", "precio": 5500}
  ]
}
```

```bash
# Reserva de 2 entradas
curl -X POST http://localhost:8080/reservas \
  -H 'Content-Type: application/json' \
  -d '{"idFuncion": 3, "cantidad": 2, "dni": "30123456"}'
```
```json
{
  "codigo": 0,
  "mensaje": "OK. Se reservaron 2 entrada(s) para la función 3",
  "reservas": [
    {"idReserva": 1, "idButaca": 1, "nroButaca": 1, "fila": 1, "columna": 1},
    {"idReserva": 2, "idButaca": 2, "nroButaca": 2, "fila": 1, "columna": 2}
  ]
}
```

Respuestas de `POST /reservas` según el código que devuelve el stored procedure:

| `codigo` | HTTP | Significado |
|---|---|---|
| 0 | 201 Created | Reserva OK |
| 1 | 400 Bad Request | Datos inválidos |
| 2 | 404 Not Found | La función no existe |
| 3 | 409 Conflict | La función no está activa o ya comenzó |
| 4 | 409 Conflict | No hay butacas suficientes |
| 99 | 500 Internal Server Error | Error inesperado (se hace rollback) |

### Casos para probar con los datos de ejemplo

| Caso | Cómo |
|---|---|
| Película sin funciones | `GET /peliculas/2020-01-01` devuelve `[]` |
| Película inexistente | `GET /peliculas/99` devuelve 404 |
| Agotar una sala | La función 5 (Sala 2) tiene 10 butacas: pedir `cantidad: 11` devuelve 409 |
| Función ya comenzada | La función 9 es de ayer: devuelve 409 |
| Función inactiva | La función 8 está cancelada: devuelve 409 |
| No aparecen en cartelera | Las funciones 10 (película inactiva) y 11 (sala inactiva) |

---

## Modelo de base de datos

Las tablas siguen el modelo lógico del enunciado: `Generos`, `Peliculas`, `Salas`, `Butacas`, `Funciones` y `Reservas`.

Restricciones pedidas:

| Requisito | Implementación |
|---|---|
| Precio por defecto 1000 y fecha actual | `Funciones.Precio DEFAULT 1000`, `Funciones.FechaProbableInicio DEFAULT CURRENT_TIMESTAMP` |
| Nombres únicos de salas, películas, géneros y butacas | `UNIQUE` en `Salas.Sala`, `Peliculas.Pelicula`, `Generos.Genero` y `(Butacas.NroButaca, IdSala)`. Una butaca se identifica por su número dentro de la sala. |
| Precio mayor a cero | `CHECK (Precio > 0)` |
| Estado `A` o `I` | `CHECK (Estado IN ('A','I'))` en salas, películas y butacas (y además en géneros y funciones) |

Decisiones de diseño:

- **Claves compuestas, como en el diagrama.** El modelo usa relaciones identificantes, así que las FK forman parte de la PK. Por ejemplo, la PK de `Funciones` es `(IdFuncion, IdPelicula, IdSala)`, y `IdFuncion` es `AUTO_INCREMENT` con `UNIQUE` (AK1). La consecuencia útil es que `Reservas` referencia a `Funciones (IdFuncion, IdPelicula, IdSala)` y a `Butacas (IdButaca, IdSala)` **con el mismo `IdSala`**. Así la base de datos garantiza que no se puede reservar una butaca de otra sala.
- **Evitar vender dos veces la misma butaca.** `Reservas.ReservaActiva` es una columna generada: vale `1` si `FechaBaja IS NULL` y `NULL` si la reserva fue cancelada. El índice `UNIQUE (IdFuncion, IdButaca, ReservaActiva)` impide dos reservas activas de la misma butaca para la misma función y deja reservar de nuevo una butaca cuya reserva se canceló. MySQL no tiene índices parciales; esta es la forma habitual de emularlos.
- **Otras validaciones:** `FechaProbableFin > FechaProbableInicio`, `Duracion > 0`, `EstaPagada IN ('S','N')`.
- **Índice** sobre `Funciones.FechaProbableInicio` para la consulta de cartelera. El SP filtra por rango (`>= fecha AND < fecha + 1 día`) en lugar de `DATE(col) = fecha`, para que el índice se pueda usar.
- `LONG VARCHAR` (columna `Actores`) es un tipo válido en MySQL, sinónimo de `MEDIUMTEXT`.

## Stored procedures

| SP | Entrada | Salida |
|---|---|---|
| `sp_PeliculasEnCartelera` | `pFecha` | IdFuncion, IdPelicula, IdSala, Pelicula, Sala, HoraInicio, Precio y, como extra, **ButacasDisponibles**. Solo incluye funciones, películas y salas activas. |
| `sp_ConsultarPelicula` | `pIdPelicula` | Result set 1: datos de la película y su género. Result set 2: sus próximas funciones. |
| `sp_ReservarFuncion` | `pIdFuncion`, `pCantidad`, `pDNI` | Result set 1: `Codigo` y `Mensaje` (OK o error). Result set 2, solo si hubo éxito: las reservas creadas con su butaca. |

Así funciona `sp_ReservarFuncion`:

1. Valida los parámetros.
2. Abre una transacción y **bloquea la fila de la función** (`SELECT ... FOR UPDATE`). Dos reservas simultáneas para la misma función se ejecutan una detrás de la otra, así que no pueden tomar la misma butaca. Lo verifiqué con 15 pedidos concurrentes sobre una sala de 10 butacas: hubo 10 reservas y 5 rechazos, sin butacas duplicadas.
3. Verifica que la función exista, que la función, la película y la sala estén activas y que la función no haya comenzado.
4. Toma las primeras `pCantidad` butacas activas y libres, ordenadas por fila y columna. Si no alcanzan, informa cuántas quedan.
5. Crea una reserva por butaca, hace `COMMIT` y devuelve el detalle. Ante cualquier error SQL, un `EXIT HANDLER` hace `ROLLBACK` y devuelve el código 99.

> **Sobre el parámetro DNI:** el enunciado pide como entrada `IdFuncion` y `Cantidad`, pero `Reservas.DNI` es `NOT NULL` en el modelo. Por eso el SP también recibe el DNI de quien reserva.

---

## Estructura del proyecto

```
.
├── cmd/api/main.go              # Arranque: config, conexión a BD con reintentos, rutas, apagado ordenado
├── internal/
│   ├── handlers/                # Endpoints HTTP, validación y traducción de códigos a status HTTP (+ tests)
│   ├── repository/              # Interfaz Repository y su implementación MySQL (llama a los SPs)
│   └── models/                  # Estructuras de request/response
├── docs/                        # openapi.yaml (embebido en el binario) + Swagger UI
├── db/                          # Scripts SQL: esquema, stored procedures y datos de prueba
├── docker-compose.yml
├── Dockerfile                   # Build multi-stage, imagen final distroless sin root
└── Makefile
```

- **Capas:** los handlers dependen de la interfaz `Repository`, no de MySQL. Por eso los tests usan un repositorio falso y no necesitan base de datos.
- **Toda la lógica de datos está en los stored procedures**, como pide el enunciado. La API valida la entrada, llama al SP y traduce el resultado a HTTP/JSON.
- **Seguridad:** todas las consultas son parametrizadas. Los errores internos se registran en el log y el cliente recibe un mensaje genérico. El cuerpo del request tiene tamaño máximo y rechaza campos desconocidos.

### Rutas `/peliculas/{fecha}` y `/peliculas/{IdPelicula}`

Las dos rutas pedidas usan la misma plantilla (`/peliculas/{x}`), así que un router no puede distinguirlas por la ruta. La API registra una sola ruta y decide por el formato del parámetro:

- `2026-09-23` (formato `AAAA-MM-DD`) devuelve la cartelera de esa fecha
- `1` (un entero) devuelve el detalle de la película
- cualquier otro valor devuelve 400

En Swagger las dos operaciones aparecen por separado, para poder probarlas cómodamente.

### Swagger

La especificación está escrita a mano en OpenAPI 3 ([`docs/openapi.yaml`](docs/openapi.yaml)) y se embebe en el binario con `go:embed`. La interfaz de Swagger UI se carga desde un CDN (jsDelivr), así que el navegador necesita acceso a internet para verla.
