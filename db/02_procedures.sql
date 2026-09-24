-- Los scripts contienen acentos: forzar UTF-8 en la conexión que los ejecuta
SET NAMES utf8mb4;

-- =============================================================================
-- Cine - Stored Procedures
-- =============================================================================
USE cine;

DROP PROCEDURE IF EXISTS sp_PeliculasEnCartelera;
DROP PROCEDURE IF EXISTS sp_ConsultarPelicula;
DROP PROCEDURE IF EXISTS sp_ReservarFuncion;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- sp_PeliculasEnCartelera
--   Películas que se proyectan en una fecha.
--   Entrada: pFecha
--   Salida : IdFuncion, IdPelicula, IdSala, Pelicula, Sala, HoraInicio, Precio
--            (+ ButacasDisponibles, para informar la disponibilidad de entradas)
--   Solo se listan funciones, películas y salas activas.
-- -----------------------------------------------------------------------------
CREATE PROCEDURE sp_PeliculasEnCartelera(IN pFecha DATE)
BEGIN
    SELECT  f.IdFuncion,
            f.IdPelicula,
            f.IdSala,
            p.Pelicula,
            s.Sala,
            TIME(f.FechaProbableInicio) AS HoraInicio,
            f.Precio,
            ( SELECT COUNT(*)
                FROM Butacas b
               WHERE b.IdSala = f.IdSala
                 AND b.Estado = 'A'
                 AND NOT EXISTS ( SELECT 1
                                    FROM Reservas r
                                   WHERE r.IdFuncion = f.IdFuncion
                                     AND r.IdButaca  = b.IdButaca
                                     AND r.FechaBaja IS NULL ) ) AS ButacasDisponibles
      FROM  Funciones f
      JOIN  Peliculas p ON p.IdPelicula = f.IdPelicula
      JOIN  Salas     s ON s.IdSala     = f.IdSala
     WHERE  f.FechaProbableInicio >= pFecha                        -- rango en lugar de DATE(col)
       AND  f.FechaProbableInicio <  pFecha + INTERVAL 1 DAY       -- para poder usar el índice
       AND  f.Estado = 'A'
       AND  p.Estado = 'A'
       AND  s.Estado = 'A'
     ORDER BY f.FechaProbableInicio, p.Pelicula;
END$$

-- -----------------------------------------------------------------------------
-- sp_ConsultarPelicula
--   Datos de una película en particular.
--   Entrada: pIdPelicula
--   Salida : 1) Datos de la película con su género.
--            2) Próximas funciones activas de la película.
--   Si la película no existe el primer result set viene vacío.
-- -----------------------------------------------------------------------------
CREATE PROCEDURE sp_ConsultarPelicula(IN pIdPelicula INT)
BEGIN
    SELECT  p.IdPelicula,
            p.Pelicula,
            p.Sinopsis,
            p.Duracion,
            p.Actores,
            p.IdGenero,
            g.Genero,
            p.Estado,
            p.Observaciones
      FROM  Peliculas p
      JOIN  Generos   g ON g.IdGenero = p.IdGenero
     WHERE  p.IdPelicula = pIdPelicula;

    SELECT  f.IdFuncion,
            f.IdSala,
            s.Sala,
            f.FechaProbableInicio,
            f.FechaProbableFin,
            f.Precio
      FROM  Funciones f
      JOIN  Salas     s ON s.IdSala = f.IdSala
     WHERE  f.IdPelicula = pIdPelicula
       AND  f.Estado = 'A'
       AND  s.Estado = 'A'
       AND  f.FechaProbableInicio >= NOW()
     ORDER BY f.FechaProbableInicio;
END$$

-- -----------------------------------------------------------------------------
-- sp_ReservarFuncion
--   Reserva "pCantidad" entradas para una función que se está proyectando.
--   Entrada: pIdFuncion, pCantidad, pDNI (el DNI es obligatorio en Reservas)
--   Salida : 1) Codigo, Mensaje   -> Codigo 0 = OK, distinto de 0 = error:
--                                     1 = datos inválidos
--                                     2 = la función no existe
--                                     3 = la función no está disponible
--                                     4 = no hay butacas suficientes
--                                    99 = error inesperado
--            2) Solo si Codigo = 0: las reservas generadas (una por butaca).
--
--   Concurrencia: la fila de la función se bloquea con SELECT ... FOR UPDATE,
--   por lo que dos reservas simultáneas para la misma función se serializan y
--   no pueden asignar la misma butaca. Además, el índice UQ_Reservas_ButacaActiva
--   lo impide a nivel de datos.
-- -----------------------------------------------------------------------------
CREATE PROCEDURE sp_ReservarFuncion(
    IN pIdFuncion INT,
    IN pCantidad  INT,
    IN pDNI       VARCHAR(11)
)
proc: BEGIN
    DECLARE vIdPelicula   INT;
    DECLARE vIdSala       SMALLINT;
    DECLARE vInicio       DATETIME;
    DECLARE vEstado       CHAR(1);
    DECLARE vPeliActiva   CHAR(1);
    DECLARE vSalaActiva   CHAR(1);
    DECLARE vDisponibles  INT;
    DECLARE vErrorMsg     TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 vErrorMsg = MESSAGE_TEXT;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmpButacasAsignadas;
        SELECT 99 AS Codigo, CONCAT('Error al registrar la reserva: ', vErrorMsg) AS Mensaje;
    END;

    -- Validaciones de parámetros -------------------------------------------------
    IF pIdFuncion IS NULL OR pIdFuncion <= 0 THEN
        SELECT 1 AS Codigo, 'El IdFuncion es inválido' AS Mensaje;
        LEAVE proc;
    END IF;

    IF pCantidad IS NULL OR pCantidad <= 0 THEN
        SELECT 1 AS Codigo, 'La cantidad de entradas debe ser mayor a cero' AS Mensaje;
        LEAVE proc;
    END IF;

    IF pDNI IS NULL OR TRIM(pDNI) = '' THEN
        SELECT 1 AS Codigo, 'El DNI es obligatorio' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Bloqueo de la función ------------------------------------------------------
    SELECT  f.IdPelicula, f.IdSala, f.FechaProbableInicio, f.Estado, p.Estado, s.Estado
      INTO  vIdPelicula, vIdSala, vInicio, vEstado, vPeliActiva, vSalaActiva
      FROM  Funciones f
      JOIN  Peliculas p ON p.IdPelicula = f.IdPelicula
      JOIN  Salas     s ON s.IdSala     = f.IdSala
     WHERE  f.IdFuncion = pIdFuncion
       FOR UPDATE OF f;

    IF vIdPelicula IS NULL THEN
        ROLLBACK;
        SELECT 2 AS Codigo, CONCAT('La función ', pIdFuncion, ' no existe') AS Mensaje;
        LEAVE proc;
    END IF;

    IF vEstado <> 'A' OR vPeliActiva <> 'A' OR vSalaActiva <> 'A' THEN
        ROLLBACK;
        SELECT 3 AS Codigo, 'La función no se encuentra activa' AS Mensaje;
        LEAVE proc;
    END IF;

    IF vInicio < NOW() THEN
        ROLLBACK;
        SELECT 3 AS Codigo, 'La función ya comenzó, no admite reservas' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Disponibilidad -------------------------------------------------------------
    DROP TEMPORARY TABLE IF EXISTS tmpButacasAsignadas;
    CREATE TEMPORARY TABLE tmpButacasAsignadas (IdButaca INT PRIMARY KEY);

    INSERT INTO tmpButacasAsignadas (IdButaca)
    SELECT  b.IdButaca
      FROM  Butacas b
     WHERE  b.IdSala = vIdSala
       AND  b.Estado = 'A'
       AND  NOT EXISTS ( SELECT 1
                           FROM Reservas r
                          WHERE r.IdFuncion = pIdFuncion
                            AND r.IdButaca  = b.IdButaca
                            AND r.FechaBaja IS NULL )
     ORDER BY b.Fila, b.Columna
     LIMIT pCantidad;

    SELECT COUNT(*) INTO vDisponibles FROM tmpButacasAsignadas;

    IF vDisponibles < pCantidad THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmpButacasAsignadas;
        SELECT 4 AS Codigo,
               CONCAT('No hay butacas suficientes. Solicitadas: ', pCantidad,
                      ', disponibles: ', vDisponibles) AS Mensaje;
        LEAVE proc;
    END IF;

    -- Registro de la reserva -----------------------------------------------------
    INSERT INTO Reservas (IdFuncion, IdPelicula, IdSala, IdButaca, DNI)
    SELECT  pIdFuncion, vIdPelicula, vIdSala, t.IdButaca, TRIM(pDNI)
      FROM  tmpButacasAsignadas t;

    COMMIT;

    SELECT 0 AS Codigo,
           CONCAT('OK. Se reservaron ', pCantidad, ' entrada(s) para la función ', pIdFuncion) AS Mensaje;

    SELECT  r.IdReserva,
            r.IdButaca,
            b.NroButaca,
            b.Fila,
            b.Columna
      FROM  Reservas r
      JOIN  tmpButacasAsignadas t ON t.IdButaca = r.IdButaca
      JOIN  Butacas b             ON b.IdButaca = r.IdButaca
     WHERE  r.IdFuncion = pIdFuncion
       AND  r.FechaBaja IS NULL
     ORDER BY b.Fila, b.Columna;

    DROP TEMPORARY TABLE IF EXISTS tmpButacasAsignadas;
END$$

DELIMITER ;
