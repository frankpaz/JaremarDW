-- 149: Bronze (stg) de la carga masiva del plan de generacion de energia.
-- A diferencia de los extracts del AS400 (que auto-provisionan stg desde la
-- metadata del origen), la fuente aqui es un Excel con un formato conocido
-- (db/etl/dimPlanGeneracion/cargar_plan_generacion.py), asi que el contrato
-- de stg se define explicitamente en una migracion.
--
-- stg.dimPlanGeneracionMensual: hoja 'Plan_Anual' del Reporte Ejecutivo
--   (kWh del mes por plantel), desagregada a una fila por plantel y mes.
-- stg.dimPlantaSolar: hoja 'PI' (catalogo de puntos de interconexion con su
--   capacidad y plantel); CodigoSitio lo asigna el cargador (mapeo PI -> sitio
--   del DW, ej. HARINAS -> harina).
-- Ambas son truncate + reload en cada carga.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimPlanGeneracionMensual'
)
BEGIN
    CREATE TABLE stg.dimPlanGeneracionMensual (
        Anio            INT            NOT NULL,
        Mes             INT            NOT NULL,
        Plantel         NVARCHAR(50)   NOT NULL,
        PlanKwh         DECIMAL(18,8)  NOT NULL,
        PlanFuente      NVARCHAR(100)  NOT NULL,
        PlanVersion     NVARCHAR(50)   NOT NULL,
        ArchivoOrigen   NVARCHAR(260)  NULL,
        FechaCargaStg   DATETIME2(7)   NOT NULL CONSTRAINT DF_dimPlanGeneracionMensual_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId           INT            NULL
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimPlantaSolar'
)
BEGIN
    CREATE TABLE stg.dimPlantaSolar (
        CodigoPI         NVARCHAR(50)   NOT NULL,
        Plantel          NVARCHAR(50)   NOT NULL,
        CodigoSitio      NVARCHAR(50)   NOT NULL,
        CapacidadDcKwp   DECIMAL(12,4)  NOT NULL,
        CapacidadAcKw    DECIMAL(12,4)  NOT NULL,
        ArchivoOrigen    NVARCHAR(260)  NULL,
        FechaCargaStg    DATETIME2(7)   NOT NULL CONSTRAINT DF_dimPlantaSolar_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId            INT            NULL
    );
END
GO
