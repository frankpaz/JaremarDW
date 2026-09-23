-- 150: Silver ([int]) del plan de generacion de energia.
-- int.dimPlantaSolar: catalogo de PI (FULL; lo que ya no viene del Excel queda
--   EsVigente = 0).
-- int.dimPlanGeneracionMensual: historial de versiones del plan. PK
--   (Anio, Mes, Plantel, PlanVersion): cargar una version nueva NO borra la
--   anterior. EsVigente = 1 solo en la version cargada mas recientemente para
--   cada (Anio, Plantel) -- ver int.usp_MergeDimPlanGeneracionMensual.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimPlantaSolar'
)
BEGIN
    CREATE TABLE [int].dimPlantaSolar (
        CodigoPI         NVARCHAR(50)   NOT NULL CONSTRAINT PK_Int_dimPlantaSolar PRIMARY KEY,
        Plantel          NVARCHAR(50)   NOT NULL,
        CodigoSitio      NVARCHAR(50)   NOT NULL,
        CapacidadDcKwp   DECIMAL(12,4)  NOT NULL,
        CapacidadAcKw    DECIMAL(12,4)  NOT NULL,
        ArchivoOrigen    NVARCHAR(260)  NULL,
        EsVigente        BIT            NOT NULL CONSTRAINT DF_Int_dimPlantaSolar_EsVigente DEFAULT (1),
        HashDiff         BINARY(32)     NOT NULL,
        FechaCargaInt    DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimPlantaSolar_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId            INT            NULL
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimPlanGeneracionMensual'
)
BEGIN
    CREATE TABLE [int].dimPlanGeneracionMensual (
        Anio             INT            NOT NULL,
        Mes              INT            NOT NULL,
        Plantel          NVARCHAR(50)   NOT NULL,
        PlanVersion      NVARCHAR(50)   NOT NULL,
        PlanKwh          DECIMAL(18,8)  NOT NULL,
        PlanFuente       NVARCHAR(100)  NOT NULL,
        ArchivoOrigen    NVARCHAR(260)  NULL,
        EsVigente        BIT            NOT NULL CONSTRAINT DF_Int_dimPlanGeneracionMensual_EsVigente DEFAULT (1),
        HashDiff         BINARY(32)     NOT NULL,
        FechaCargaInt    DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimPlanGeneracionMensual_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId            INT            NULL,
        CONSTRAINT PK_Int_dimPlanGeneracionMensual PRIMARY KEY (Anio, Mes, Plantel, PlanVersion),
        CONSTRAINT CK_Int_dimPlanGeneracionMensual_Mes CHECK (Mes BETWEEN 1 AND 12)
    );
END
GO
