-- 150: Silver ([int]) del plan de generacion de energia.
-- int.dimPlanGeneracion: historial de versiones del plan diario por inversor.
-- PK (Fecha, CodigoInversor, PlanVersion): cargar una version nueva NO borra las
-- anteriores. EsVigente = 1 solo en la version cargada mas recientemente para
-- cada (Fecha, CodigoInversor) -- ver int.usp_MergeDimPlanGeneracion.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimPlanGeneracion'
)
BEGIN
    CREATE TABLE [int].dimPlanGeneracion (
        Fecha            DATE           NOT NULL,
        CodigoInversor   NVARCHAR(50)   NOT NULL,
        PlanVersion      NVARCHAR(50)   NOT NULL,
        SerialInversor   NVARCHAR(50)   NULL,
        PlanKwh          DECIMAL(18,8)  NOT NULL,
        PlanFuente       NVARCHAR(100)  NOT NULL,
        ArchivoOrigen    NVARCHAR(260)  NULL,
        EsVigente        BIT            NOT NULL CONSTRAINT DF_Int_dimPlanGeneracion_EsVigente DEFAULT (1),
        HashDiff         BINARY(32)     NOT NULL,
        FechaCargaInt    DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimPlanGeneracion_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId            INT            NULL,
        CONSTRAINT PK_Int_dimPlanGeneracion PRIMARY KEY (Fecha, CodigoInversor, PlanVersion)
    );
END
GO
