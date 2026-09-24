-- 155: redefine dimPlanGeneracion a partir del archivo 'Plan Produccion Energetica
-- - Calculos.xlsx' (Sheet1, columnas marcadas en verde). Cambio ADITIVO: solo agrega
-- columnas nullable y conserva las existentes (Fecha, CodigoInversor, PlanKwh,
-- SmaDeviceKey, DeviceCapacityKey, EsVigente, ...), porque las vistas del reporte
-- (dw.vwRptPlanPlantaDia y las que dependen de ella) leen esta tabla.
--
-- Correspondencia con las columnas verdes del archivo:
--   Planta             -> Planta
--   Proveedor          -> Proveedor          (sma / huawei / growatt / soliscloud)
--   Inversor           -> DispositivoId      (llave del dispositivo en el fabricante)
--   InversorId         -> CodigoInversor     (ya existia: HARINA-1, JABON-3, ...)
--   Mes / NombreMes    -> Mes / NombreMes
--   Ubicacion          -> Ubicacion          (KM13.5 / KM15 / NA)
--   PlanDiarioAsignado -> PlanDiarioAsignado (plan diario de la PLANTA; se repite en
--                         cada inversor de la planta: NO sumar entre inversores)
--   PlanDiarioInversor -> PlanKwh            (ya existia; plan diario del inversor)
-- El archivo no trae anio: se indica al cargar y cada mes se expande a sus dias
-- reales (Fecha), igual que la version anterior de la tabla.
-- dw agrega ademas HuaweiDeviceKey y SoliscloudDeviceKey (llaves a las dimensiones
-- de cada fabricante); SMA sigue en SmaDeviceKey y Growatt en DeviceCapacityKey.
-- Idempotente.

-- stg
IF COL_LENGTH('stg.dimPlanGeneracion', 'Planta') IS NULL
    ALTER TABLE stg.dimPlanGeneracion ADD
        Planta              NVARCHAR(50)   NULL,
        Proveedor           NVARCHAR(30)   NULL,
        DispositivoId       NVARCHAR(50)   NULL,
        Ubicacion           NVARCHAR(20)   NULL,
        Mes                 INT            NULL,
        NombreMes           NVARCHAR(20)   NULL,
        PlanDiarioAsignado  DECIMAL(18,8)  NULL;
GO

-- int
IF COL_LENGTH('int.dimPlanGeneracion', 'Planta') IS NULL
    ALTER TABLE [int].dimPlanGeneracion ADD
        Planta              NVARCHAR(50)   NULL,
        Proveedor           NVARCHAR(30)   NULL,
        DispositivoId       NVARCHAR(50)   NULL,
        Ubicacion           NVARCHAR(20)   NULL,
        Mes                 INT            NULL,
        NombreMes           NVARCHAR(20)   NULL,
        PlanDiarioAsignado  DECIMAL(18,8)  NULL;
GO

-- dw
IF COL_LENGTH('dw.dimPlanGeneracion', 'Planta') IS NULL
    ALTER TABLE dw.dimPlanGeneracion ADD
        Planta               NVARCHAR(50)   NULL,
        Proveedor            NVARCHAR(30)   NULL,
        DispositivoId        NVARCHAR(50)   NULL,
        Ubicacion            NVARCHAR(20)   NULL,
        Mes                  INT            NULL,
        NombreMes            NVARCHAR(20)   NULL,
        PlanDiarioAsignado   DECIMAL(18,8)  NULL,
        HuaweiDeviceKey      INT            NULL,
        SoliscloudDeviceKey  INT            NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_dw_dimPlanGeneracion_Planta' AND object_id = OBJECT_ID('dw.dimPlanGeneracion'))
    CREATE INDEX IX_dw_dimPlanGeneracion_Planta ON dw.dimPlanGeneracion (Planta, Fecha) WHERE EsVigente = 1;
GO
