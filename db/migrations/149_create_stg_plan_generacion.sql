-- 149: Bronze (stg) de la carga masiva del plan de generacion de energia.
-- A diferencia de los extracts del AS400 (que auto-provisionan stg desde la
-- metadata del origen), la fuente aqui es un Excel con un formato conocido
-- (db/etl/dimPlanGeneracion/cargar_plan_generacion.py), asi que el contrato
-- de stg se define explicitamente en una migracion.
--
-- stg.dimPlanGeneracion: hoja 'Plan_Diario_INV' del Reporte Ejecutivo (plan de
-- energia en kWh por dia de cada inversor), desagregada a una fila por fecha e
-- inversor. SerialInversor (opcional) viene de la hoja 'Inversores' del mismo
-- Excel y sirve de respaldo para enlazar el inversor con dimSmaDevices cuando el
-- portal SMA no le puso el ID en el nombre. Es truncate + reload en cada carga.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'stg' AND t.name = 'dimPlanGeneracion'
)
BEGIN
    CREATE TABLE stg.dimPlanGeneracion (
        Fecha            DATE           NOT NULL,
        CodigoInversor   NVARCHAR(50)   NOT NULL,
        SerialInversor   NVARCHAR(50)   NULL,
        PlanKwh          DECIMAL(18,8)  NOT NULL,
        PlanFuente       NVARCHAR(100)  NOT NULL,
        PlanVersion      NVARCHAR(50)   NOT NULL,
        ArchivoOrigen    NVARCHAR(260)  NULL,
        FechaCargaStg    DATETIME2(7)   NOT NULL CONSTRAINT DF_dimPlanGeneracion_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId            INT            NULL
    );
END
GO
