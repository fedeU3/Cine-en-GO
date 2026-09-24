-- Los scripts contienen acentos: forzar UTF-8 en la conexión que los ejecuta
SET NAMES utf8mb4;

-- =============================================================================
-- Cine - Datos de prueba
-- Las funciones se generan relativas a la fecha actual (hoy, mañana y pasado)
-- para que siempre haya cartelera disponible al levantar el proyecto.
-- =============================================================================
USE cine;

INSERT INTO Generos (IdGenero, Genero, Estado) VALUES
    (1, 'Acción',           'A'),
    (2, 'Comedia',          'A'),
    (3, 'Drama',            'A'),
    (4, 'Ciencia Ficción',  'A'),
    (5, 'Animación',        'A');

-- TipoSala: 'N' = Normal, '3' = 3D, 'I' = IMAX
INSERT INTO Salas (IdSala, Sala, TipoSala, Direccion, Estado, Observaciones) VALUES
    (1, 'Sala 1',    'N', 'Av. Corrientes 1234', 'A', NULL),
    (2, 'Sala 2 3D', '3', 'Av. Corrientes 1234', 'A', 'Sala chica, ideal para probar agotamiento'),
    (3, 'Sala IMAX', 'I', 'Av. Corrientes 1234', 'I', 'En remodelación');

-- Butacas: Sala 1 = 5 filas x 8 columnas (40), Sala 2 = 2 filas x 5 columnas (10),
--          Sala 3 = 3 filas x 4 columnas (12). La butaca 8 de la Sala 1 está inactiva.
INSERT INTO Butacas (IdButaca, IdSala, NroButaca, Fila, Columna, Estado)
WITH RECURSIVE n AS (SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 40)
SELECT i,        1, i, (i - 1) DIV 8 + 1, (i - 1) MOD 8 + 1, IF(i = 8, 'I', 'A') FROM n
UNION ALL
SELECT 100 + i,  2, i, (i - 1) DIV 5 + 1, (i - 1) MOD 5 + 1, 'A' FROM n WHERE i <= 10
UNION ALL
SELECT 200 + i,  3, i, (i - 1) DIV 4 + 1, (i - 1) MOD 4 + 1, 'A' FROM n WHERE i <= 12;

INSERT INTO Peliculas (IdPelicula, IdGenero, Pelicula, Sinopsis, Duracion, Actores, Estado) VALUES
    (1, 4, 'Interestelar',
        'Un grupo de exploradores viaja a través de un agujero de gusano en busca de un nuevo hogar para la humanidad.',
        169, 'Matthew McConaughey, Anne Hathaway, Jessica Chastain', 'A'),
    (2, 1, 'Mad Max: Furia en el camino',
        'En un mundo postapocalíptico, Furiosa y Max huyen de un tirano a través del desierto.',
        120, 'Tom Hardy, Charlize Theron, Nicholas Hoult', 'A'),
    (3, 5, 'Intensa-Mente',
        'Las emociones de Riley intentan guiarla durante un cambio difícil en su vida.',
        95, 'Amy Poehler, Phyllis Smith, Bill Hader', 'A'),
    (4, 3, 'Relatos Salvajes',
        'Seis historias sobre personas que pierden el control ante situaciones límite.',
        122, 'Ricardo Darín, Leonardo Sbaraglia, Érica Rivas', 'A'),
    (5, 2, 'Película Retirada',
        'Película dada de baja, no debe aparecer en cartelera.',
        90, 'N/A', 'I');

-- Funciones (IdFuncion es AUTO_INCREMENT; el orden de inserción define el Id)
INSERT INTO Funciones (IdPelicula, IdSala, FechaProbableInicio, FechaProbableFin, Precio, Estado, Observaciones) VALUES
    -- Hoy (tarde-noche, para que admitan reservas)
    (1, 1, CURDATE() + INTERVAL 23 HOUR,                     CURDATE() + INTERVAL 23 HOUR + INTERVAL 169 MINUTE, 5500, 'A', NULL),
    (3, 2, CURDATE() + INTERVAL 22 HOUR + INTERVAL 30 MINUTE, CURDATE() + INTERVAL 24 HOUR + INTERVAL 5 MINUTE,  4800, 'A', NULL),
    -- Mañana
    (1, 1, CURDATE() + INTERVAL 1 DAY + INTERVAL 18 HOUR,     CURDATE() + INTERVAL 1 DAY + INTERVAL 21 HOUR,     5500, 'A', NULL),
    (2, 1, CURDATE() + INTERVAL 1 DAY + INTERVAL 21 HOUR + INTERVAL 30 MINUTE,
                                                              CURDATE() + INTERVAL 1 DAY + INTERVAL 23 HOUR + INTERVAL 30 MINUTE, 6000, 'A', NULL),
    (3, 2, CURDATE() + INTERVAL 1 DAY + INTERVAL 16 HOUR,     CURDATE() + INTERVAL 1 DAY + INTERVAL 17 HOUR + INTERVAL 35 MINUTE, 4800, 'A', NULL),
    (4, 2, CURDATE() + INTERVAL 1 DAY + INTERVAL 20 HOUR,     CURDATE() + INTERVAL 1 DAY + INTERVAL 22 HOUR + INTERVAL 2 MINUTE,  DEFAULT, 'A', 'Usa el precio por defecto'),
    -- Pasado mañana
    (4, 1, CURDATE() + INTERVAL 2 DAY + INTERVAL 19 HOUR,     CURDATE() + INTERVAL 2 DAY + INTERVAL 21 HOUR + INTERVAL 2 MINUTE,  5000, 'A', NULL),
    (2, 1, CURDATE() + INTERVAL 2 DAY + INTERVAL 22 HOUR,     CURDATE() + INTERVAL 3 DAY,                         6000, 'I', 'Función cancelada'),
    -- Ayer (ya proyectada, no admite reservas)
    (2, 1, CURDATE() - INTERVAL 1 DAY + INTERVAL 20 HOUR,     CURDATE() - INTERVAL 1 DAY + INTERVAL 22 HOUR,     6000, 'A', NULL),
    -- Película inactiva y sala inactiva (no deben aparecer en cartelera)
    (5, 1, CURDATE() + INTERVAL 1 DAY + INTERVAL 14 HOUR,     CURDATE() + INTERVAL 1 DAY + INTERVAL 15 HOUR + INTERVAL 30 MINUTE, 3000, 'A', NULL),
    (1, 3, CURDATE() + INTERVAL 1 DAY + INTERVAL 19 HOUR,     CURDATE() + INTERVAL 1 DAY + INTERVAL 22 HOUR,     9000, 'A', NULL);
