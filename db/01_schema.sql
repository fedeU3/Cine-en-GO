-- Los scripts contienen acentos: forzar UTF-8 en la conexión que los ejecuta
SET NAMES utf8mb4;

-- =============================================================================
-- Cine - Modelo de base de datos (MySQL 8.0.16+)
-- =============================================================================
-- Sigue el modelo lógico del enunciado. Las relaciones son "identificantes"
-- (las FK forman parte de la PK), por eso Funciones, Butacas y Reservas tienen
-- claves primarias compuestas y un identificador propio único (AK1).
-- =============================================================================

CREATE DATABASE IF NOT EXISTS cine
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE cine;

-- -----------------------------------------------------------------------------
-- Generos
-- -----------------------------------------------------------------------------
CREATE TABLE Generos (
    IdGenero  SMALLINT    NOT NULL,
    Genero    VARCHAR(50) NOT NULL,
    Estado    CHAR(1)     NOT NULL DEFAULT 'A',
    CONSTRAINT PK_Generos        PRIMARY KEY (IdGenero),
    CONSTRAINT AK1_Generos       UNIQUE (Genero),
    CONSTRAINT CK_Generos_Estado CHECK (Estado IN ('A', 'I'))
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Salas
-- -----------------------------------------------------------------------------
CREATE TABLE Salas (
    IdSala        SMALLINT     NOT NULL,
    Sala          VARCHAR(60)  NOT NULL,
    TipoSala      CHAR(1)      NOT NULL,
    Direccion     VARCHAR(60)  NOT NULL,
    Estado        CHAR(1)      NOT NULL DEFAULT 'A',
    Observaciones VARCHAR(255) NULL,
    CONSTRAINT PK_Salas        PRIMARY KEY (IdSala),
    CONSTRAINT AK1_Salas       UNIQUE (Sala),
    CONSTRAINT CK_Salas_Estado CHECK (Estado IN ('A', 'I'))
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Peliculas
-- -----------------------------------------------------------------------------
CREATE TABLE Peliculas (
    IdPelicula    INTEGER      NOT NULL,
    IdGenero      SMALLINT     NOT NULL,
    Pelicula      VARCHAR(100) NOT NULL,
    Sinopsis      TEXT         NOT NULL,
    Duracion      SMALLINT     NOT NULL,           -- en minutos
    Actores       LONG VARCHAR NOT NULL,           -- LONG VARCHAR = MEDIUMTEXT en MySQL
    Estado        CHAR(1)      NOT NULL DEFAULT 'A',
    Observaciones VARCHAR(255) NULL,
    CONSTRAINT PK_Peliculas          PRIMARY KEY (IdPelicula),
    CONSTRAINT AK1_Peliculas         UNIQUE (Pelicula),
    CONSTRAINT FK_Peliculas_Generos  FOREIGN KEY (IdGenero) REFERENCES Generos (IdGenero),
    CONSTRAINT CK_Peliculas_Estado   CHECK (Estado IN ('A', 'I')),
    CONSTRAINT CK_Peliculas_Duracion CHECK (Duracion > 0)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Butacas
--   PK  : (IdButaca, IdSala)   -> relación identificante con Salas
--   AK1 : IdButaca
--   AK2 : (NroButaca, IdSala)  -> no puede repetirse el número de butaca en una sala
-- -----------------------------------------------------------------------------
CREATE TABLE Butacas (
    IdButaca      INTEGER      NOT NULL,
    IdSala        SMALLINT     NOT NULL,
    NroButaca     SMALLINT     NOT NULL,
    Fila          SMALLINT     NOT NULL,
    Columna       SMALLINT     NOT NULL,
    Estado        CHAR(1)      NOT NULL DEFAULT 'A',
    Observaciones VARCHAR(255) NULL,
    CONSTRAINT PK_Butacas        PRIMARY KEY (IdButaca, IdSala),
    CONSTRAINT AK1_Butacas       UNIQUE (IdButaca),
    CONSTRAINT AK2_Butacas       UNIQUE (NroButaca, IdSala),
    CONSTRAINT FK_Butacas_Salas  FOREIGN KEY (IdSala) REFERENCES Salas (IdSala),
    CONSTRAINT CK_Butacas_Estado CHECK (Estado IN ('A', 'I'))
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Funciones
--   PK  : (IdFuncion, IdPelicula, IdSala)
--   AK1 : IdFuncion (IDENTITY)
--   Defaults: Precio = 1000 y FechaProbableInicio = fecha actual.
-- -----------------------------------------------------------------------------
CREATE TABLE Funciones (
    IdFuncion           INTEGER       NOT NULL AUTO_INCREMENT,
    IdPelicula          INTEGER       NOT NULL,
    IdSala              SMALLINT      NOT NULL,
    FechaProbableInicio DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FechaProbableFin    DATETIME      NOT NULL,
    FechaInicio         DATETIME      NULL,
    FechaFin            DATETIME      NULL,
    Precio              DECIMAL(12,2) NOT NULL DEFAULT 1000,
    Estado              CHAR(1)       NOT NULL DEFAULT 'A',
    Observaciones       VARCHAR(255)  NULL,
    CONSTRAINT PK_Funciones           PRIMARY KEY (IdFuncion, IdPelicula, IdSala),
    CONSTRAINT AK1_Funciones          UNIQUE (IdFuncion),
    CONSTRAINT FK_Funciones_Peliculas FOREIGN KEY (IdPelicula) REFERENCES Peliculas (IdPelicula),
    CONSTRAINT FK_Funciones_Salas     FOREIGN KEY (IdSala)     REFERENCES Salas (IdSala),
    CONSTRAINT CK_Funciones_Precio    CHECK (Precio > 0),
    CONSTRAINT CK_Funciones_Estado    CHECK (Estado IN ('A', 'I')),
    CONSTRAINT CK_Funciones_Fechas    CHECK (FechaProbableFin > FechaProbableInicio),
    INDEX IX_Funciones_FechaProbableInicio (FechaProbableInicio)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- Reservas
--   PK  : (IdReserva, IdFuncion, IdPelicula, IdSala, IdButaca)
--   AK1 : IdReserva (IDENTITY)
--   La FK compuesta a Funciones (IdFuncion, IdPelicula, IdSala) y la FK compuesta
--   a Butacas (IdButaca, IdSala) comparten IdSala: esto garantiza a nivel de BD
--   que la butaca reservada pertenece a la sala donde se proyecta la función.
--
--   ReservaActiva es una columna generada: vale 1 si la reserva no fue dada de
--   baja y NULL en caso contrario. Como un índice UNIQUE admite varios NULL,
--   UQ_Reservas_ButacaActiva impide vender dos veces la misma butaca para la
--   misma función, pero permite volver a reservarla si la anterior se canceló.
-- -----------------------------------------------------------------------------
CREATE TABLE Reservas (
    IdReserva     BIGINT       NOT NULL AUTO_INCREMENT,
    IdFuncion     INTEGER      NOT NULL,
    IdPelicula    INTEGER      NOT NULL,
    IdSala        SMALLINT     NOT NULL,
    IdButaca      INTEGER      NOT NULL,
    DNI           VARCHAR(11)  NOT NULL,
    FechaAlta     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FechaBaja     DATETIME     NULL,
    EstaPagada    CHAR(1)      NOT NULL DEFAULT 'N',
    Observaciones VARCHAR(255) NULL,
    ReservaActiva TINYINT AS (IF(FechaBaja IS NULL, 1, NULL)) STORED,
    CONSTRAINT PK_Reservas            PRIMARY KEY (IdReserva, IdFuncion, IdPelicula, IdSala, IdButaca),
    CONSTRAINT AK1_Reservas           UNIQUE (IdReserva),
    CONSTRAINT UQ_Reservas_ButacaActiva UNIQUE (IdFuncion, IdButaca, ReservaActiva),
    CONSTRAINT FK_Reservas_Funciones  FOREIGN KEY (IdFuncion, IdPelicula, IdSala)
        REFERENCES Funciones (IdFuncion, IdPelicula, IdSala),
    CONSTRAINT FK_Reservas_Butacas    FOREIGN KEY (IdButaca, IdSala)
        REFERENCES Butacas (IdButaca, IdSala),
    CONSTRAINT CK_Reservas_EstaPagada CHECK (EstaPagada IN ('S', 'N')),
    CONSTRAINT CK_Reservas_Baja       CHECK (FechaBaja IS NULL OR FechaBaja >= FechaAlta)
) ENGINE = InnoDB;
