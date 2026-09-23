-- 152: Gold (dw) del plan de generacion de energia.
-- dw.dimPlantaSolar: catalogo de puntos de interconexion (PI). CapacidadDcKwp
--   es la base del reparto del plan de cada plantel entre sus PI (misma regla
--   que usa el Reporte Ejecutivo); CodigoSitio enlaza con los sitios del dominio
--   Solar (dimGhiPlanDaily, factMeteoDaily). Un PI que no esta en el plan
--   operativo (ej. bodega-jabon) simplemente no aparece aqui.
-- dw.dimPlanGeneracionMensual: plan de energia del mes (kWh) por plantel, con
--   historial de versiones; EsVigente marca la version en uso.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimPlantaSolar'
)
BEGIN
    CREATE TABLE dw.dimPlantaSolar (
        PlantaKey        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlantaSolar PRIMARY KEY,
        CodigoPI          NVARCHAR(50)   NOT NULL,
        Plantel           NVARCHAR(50)   NOT NULL,
        CodigoSitio       NVARCHAR(50)   NOT NULL,
        CapacidadDcKwp    DECIMAL(12,4)  NOT NULL,
        CapacidadAcKw     DECIMAL(12,4)  NOT NULL,
        EsVigente         BIT            NOT NULL CONSTRAINT DF_dw_dimPlantaSolar_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)     NOT NULL,
        FechaCargaDw      DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimPlantaSolar_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT            NULL,
        CONSTRAINT UQ_dw_dimPlantaSolar_CodigoPI UNIQUE (CodigoPI)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimPlanGeneracionMensual'
)
BEGIN
    CREATE TABLE dw.dimPlanGeneracionMensual (
        PlanKey           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlanGeneracionMensual PRIMARY KEY,
        Anio              INT            NOT NULL,
        Mes               INT            NOT NULL,
        Plantel           NVARCHAR(50)   NOT NULL,
        PlanVersion       NVARCHAR(50)   NOT NULL,
        PlanKwh           DECIMAL(18,8)  NOT NULL,
        PlanFuente        NVARCHAR(100)  NOT NULL,
        ArchivoOrigen     NVARCHAR(260)  NULL,
        EsVigente         BIT            NOT NULL CONSTRAINT DF_dw_dimPlanGeneracionMensual_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)     NOT NULL,
        FechaCargaDw      DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimPlanGeneracionMensual_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT            NULL,
        CONSTRAINT UQ_dw_dimPlanGeneracionMensual UNIQUE (Anio, Mes, Plantel, PlanVersion),
        CONSTRAINT CK_dw_dimPlanGeneracionMensual_Mes CHECK (Mes BETWEEN 1 AND 12)
    );
END
GO
