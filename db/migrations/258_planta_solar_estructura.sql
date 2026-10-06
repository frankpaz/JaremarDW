-- 258: catalogo de plantas del dominio Solar. Estructura; los procedimientos van en la 259 y las vistas
-- del informe en la 260.
--
-- Decisiones del usuario (2026-10-06):
--   * No hay catalogo de inversores: los inversores salen solos de las dimensiones de cada portal
--     (SMA, Huawei, Soliscloud y los equipos del hecho Growatt), con el numero de serie como nombre.
--   * Lo unico manual es un Excel ("Catalogo Plantas Solares") que carga
--     db/etl/dimPlantaSolar/cargar_plantas_solares.py:
--       - hoja Plantas: Planta, Plantel, Orden, MeteoSite, EnReporte (datos que ningun portal tiene);
--       - hoja Origen : Proveedor + CodigoOrigen (agrupador del portal: SMA PlantId, Huawei StationCode,
--                       Soliscloud StationId; en Growatt, que no tiene agrupador, el serial del equipo)
--                       -> Planta. Planta vacia = agrupador excluido a proposito (ej. PI1-MARGARINA).
--   * Capacidad: la del portal cuando la informa; si no, dw.dimDeviceCapacity (proceso externo). Para
--     Huawei la capacidad viene en el hecho (KpiData.installed_capacity): dimHuaweiDevices la guarda en
--     InstalledCapacityKwp (ultimo valor > 0 del equipo).
-- Carga FULL: lo que no viene en el Excel queda con EsVigente = 0 (nunca se borra).

-- stg -------------------------------------------------------------------------------------------
IF OBJECT_ID('stg.dimPlantaSolar', 'U') IS NULL
    CREATE TABLE stg.dimPlantaSolar (
        Planta          NVARCHAR(30)  NULL,
        Plantel         NVARCHAR(30)  NULL,
        Orden           INT           NULL,
        MeteoSite       NVARCHAR(50)  NULL,
        EnReporte       BIT           NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        FechaCargaStg   DATETIME2(7)  NOT NULL CONSTRAINT DF_stg_dimPlantaSolar_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );

IF OBJECT_ID('stg.dimPlantaSolarOrigen', 'U') IS NULL
    CREATE TABLE stg.dimPlantaSolarOrigen (
        Proveedor       VARCHAR(20)   NULL,
        CodigoOrigen    NVARCHAR(200) NULL,
        NombreOrigen    NVARCHAR(500) NULL,
        Planta          NVARCHAR(30)  NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        FechaCargaStg   DATETIME2(7)  NOT NULL CONSTRAINT DF_stg_dimPlantaSolarOrigen_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );

-- [int] -----------------------------------------------------------------------------------------
IF OBJECT_ID('[int].dimPlantaSolar', 'U') IS NULL
    CREATE TABLE [int].dimPlantaSolar (
        Planta          NVARCHAR(30)  NOT NULL CONSTRAINT PK_Int_dimPlantaSolar PRIMARY KEY,
        Plantel         NVARCHAR(30)  NULL,
        Orden           INT           NULL,
        MeteoSite       NVARCHAR(50)  NULL,
        EnReporte       BIT           NOT NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimPlantaSolar_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimPlantaSolar_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );

IF OBJECT_ID('[int].dimPlantaSolarOrigen', 'U') IS NULL
    CREATE TABLE [int].dimPlantaSolarOrigen (
        Proveedor       VARCHAR(20)   NOT NULL,
        CodigoOrigen    NVARCHAR(200) NOT NULL,
        NombreOrigen    NVARCHAR(500) NULL,
        Planta          NVARCHAR(30)  NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimPlantaSolarOrigen_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimPlantaSolarOrigen_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT PK_Int_dimPlantaSolarOrigen PRIMARY KEY (Proveedor, CodigoOrigen)
    );

-- dw --------------------------------------------------------------------------------------------
IF OBJECT_ID('dw.dimPlantaSolar', 'U') IS NULL
    CREATE TABLE dw.dimPlantaSolar (
        PlantaSolarKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlantaSolar PRIMARY KEY,
        Planta          NVARCHAR(30)  NOT NULL,
        Plantel         NVARCHAR(30)  NULL,
        Orden           INT           NULL,
        MeteoSite       NVARCHAR(50)  NULL,
        EnReporte       BIT           NOT NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_dw_dimPlantaSolar_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimPlantaSolar_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_dimPlantaSolar_Planta UNIQUE (Planta)
    );

IF OBJECT_ID('dw.dimPlantaSolarOrigen', 'U') IS NULL
    CREATE TABLE dw.dimPlantaSolarOrigen (
        PlantaSolarOrigenKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlantaSolarOrigen PRIMARY KEY,
        Proveedor       VARCHAR(20)   NOT NULL,
        CodigoOrigen    NVARCHAR(200) NOT NULL,
        NombreOrigen    NVARCHAR(500) NULL,
        Planta          NVARCHAR(30)  NULL,
        PlantaSolarKey  INT           NULL,
        ArchivoOrigen   NVARCHAR(260) NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_dw_dimPlantaSolarOrigen_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaDw    DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimPlantaSolarOrigen_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT UQ_dw_dimPlantaSolarOrigen UNIQUE (Proveedor, CodigoOrigen)
    );

-- Huawei: capacidad informada por el portal ------------------------------------------------------
IF COL_LENGTH('[int].dimHuaweiDevices', 'InstalledCapacityKwp') IS NULL
    ALTER TABLE [int].dimHuaweiDevices ADD InstalledCapacityKwp DECIMAL(12,3) NULL;
IF COL_LENGTH('dw.dimHuaweiDevices', 'InstalledCapacityKwp') IS NULL
    ALTER TABLE dw.dimHuaweiDevices ADD InstalledCapacityKwp DECIMAL(12,3) NULL;
GO
