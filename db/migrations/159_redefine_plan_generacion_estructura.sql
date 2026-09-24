-- 159: redefine dimPlanGeneracion para que sea FIEL al Excel de origen ('Plan Produccion
-- Energetica - Calculos.xlsx', Sheet1): solo los 9 campos marcados en verde, con los nombres
-- del Excel, mas la fecha del dia (el archivo trae el mes; se expande a dias reales) y las
-- columnas de auditoria. Se eliminan los campos anteriores que no vienen del Excel
-- (CodigoInversor -> InversorId, DispositivoId -> Inversor, PlanKwh -> PlanDiarioInversor,
-- SerialInversor y las llaves SmaDeviceKey / HuaweiDeviceKey / SoliscloudDeviceKey /
-- DeviceCapacityKey) para evitar confusion y malos calculos.
--
--   Excel                 Tabla
--   Planta                Planta
--   Proveedor             Proveedor
--   Inversor              Inversor              (llave del dispositivo en el fabricante)
--   InversorId            InversorId            (nombre del inversor: HARINA-1, ...)
--   Mes / NombreMes       Mes / NombreMes
--   Ubicación             Ubicacion             (sin tilde, por compatibilidad de identificadores)
--   PlanDiarioAsignado    PlanDiarioAsignado    (plan diario de la PLANTA, repetido en cada inversor)
--   PlanDiarioInversor    PlanDiarioInversor
--   (no viene del Excel)  Fecha                 (dia del mes, generado con --anio)
--
-- Auditoria: PlanFuente, PlanVersion, ArchivoOrigen, EsVigente, HashDiff, FechaCarga*, RunId
-- (y PlanKey como llave tecnica en dw). Los valores de plan admiten NULL: una celda con error de
-- Excel se guarda como NULL, no como 0.
--
-- Las tablas se recrean (los datos se recargan desde el Excel con el cargador). La vista de
-- reporte dw.vwRptPlanPlantaDia (definida fuera de las migraciones) se reescribe aqui, en la
-- misma transaccion, si existe: mantiene sus columnas (Planta, Fecha, PlanKwh,
-- InversoresConPlan) y ya no depende de las llaves a dispositivos.

-- 1) objetos que dependen de la estructura anterior
DROP VIEW IF EXISTS dw.vwPlanDiarioPlantel;
DROP VIEW IF EXISTS dw.vwPlanDiarioPI;
DROP VIEW IF EXISTS dw.vwPlanDiarioInversor;
GO

-- 2) tablas nuevas (solo si aun tienen la estructura anterior o no existen)
IF COL_LENGTH('dw.dimPlanGeneracion', 'InversorId') IS NULL
BEGIN
    DROP TABLE IF EXISTS dw.dimPlanGeneracion;
    DROP TABLE IF EXISTS [int].dimPlanGeneracion;
    DROP TABLE IF EXISTS stg.dimPlanGeneracion;

    CREATE TABLE stg.dimPlanGeneracion (
        Fecha               DATE           NOT NULL,
        Planta              NVARCHAR(50)   NOT NULL,
        Proveedor           NVARCHAR(30)   NOT NULL,
        Inversor            NVARCHAR(50)   NOT NULL,
        InversorId          NVARCHAR(50)   NOT NULL,
        Mes                 INT            NOT NULL,
        NombreMes           NVARCHAR(20)   NOT NULL,
        Ubicacion           NVARCHAR(20)   NOT NULL,
        PlanDiarioAsignado  DECIMAL(18,8)  NULL,
        PlanDiarioInversor  DECIMAL(18,8)  NULL,
        PlanFuente          NVARCHAR(100)  NOT NULL,
        PlanVersion         NVARCHAR(50)   NOT NULL,
        ArchivoOrigen       NVARCHAR(260)  NULL,
        FechaCargaStg       DATETIME2(7)   NOT NULL CONSTRAINT DF_dimPlanGeneracion_FechaCargaStg DEFAULT (SYSDATETIME()),
        RunId               INT            NULL
    );

    CREATE TABLE [int].dimPlanGeneracion (
        Fecha               DATE           NOT NULL,
        Planta              NVARCHAR(50)   NOT NULL,
        Proveedor           NVARCHAR(30)   NOT NULL,
        Inversor            NVARCHAR(50)   NOT NULL,
        InversorId          NVARCHAR(50)   NOT NULL,
        Mes                 INT            NOT NULL,
        NombreMes           NVARCHAR(20)   NOT NULL,
        Ubicacion           NVARCHAR(20)   NOT NULL,
        PlanDiarioAsignado  DECIMAL(18,8)  NULL,
        PlanDiarioInversor  DECIMAL(18,8)  NULL,
        PlanFuente          NVARCHAR(100)  NOT NULL,
        PlanVersion         NVARCHAR(50)   NOT NULL,
        ArchivoOrigen       NVARCHAR(260)  NULL,
        EsVigente           BIT            NOT NULL CONSTRAINT DF_Int_dimPlanGeneracion_EsVigente DEFAULT (1),
        HashDiff            BINARY(32)     NOT NULL,
        FechaCargaInt       DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimPlanGeneracion_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId               INT            NULL,
        CONSTRAINT PK_Int_dimPlanGeneracion PRIMARY KEY (Fecha, InversorId, PlanVersion),
        CONSTRAINT CK_Int_dimPlanGeneracion_Mes CHECK (Mes BETWEEN 1 AND 12)
    );

    CREATE TABLE dw.dimPlanGeneracion (
        PlanKey             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlanGeneracion PRIMARY KEY,
        Fecha               DATE           NOT NULL,
        Planta              NVARCHAR(50)   NOT NULL,
        Proveedor           NVARCHAR(30)   NOT NULL,
        Inversor            NVARCHAR(50)   NOT NULL,
        InversorId          NVARCHAR(50)   NOT NULL,
        Mes                 INT            NOT NULL,
        NombreMes           NVARCHAR(20)   NOT NULL,
        Ubicacion           NVARCHAR(20)   NOT NULL,
        PlanDiarioAsignado  DECIMAL(18,8)  NULL,
        PlanDiarioInversor  DECIMAL(18,8)  NULL,
        PlanFuente          NVARCHAR(100)  NOT NULL,
        PlanVersion         NVARCHAR(50)   NOT NULL,
        ArchivoOrigen       NVARCHAR(260)  NULL,
        EsVigente           BIT            NOT NULL CONSTRAINT DF_dw_dimPlanGeneracion_EsVigente DEFAULT (1),
        HashDiff            BINARY(32)     NOT NULL,
        FechaCargaDw        DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimPlanGeneracion_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId               INT            NULL,
        CONSTRAINT UQ_dw_dimPlanGeneracion UNIQUE (Fecha, InversorId, PlanVersion),
        CONSTRAINT CK_dw_dimPlanGeneracion_Mes CHECK (Mes BETWEEN 1 AND 12)
    );
    CREATE INDEX IX_dw_dimPlanGeneracion_Planta ON dw.dimPlanGeneracion (Planta, Fecha) WHERE EsVigente = 1;
END
GO

-- 3) vista del reporte (si existe en este ambiente): misma salida, sin llaves a dispositivos
IF OBJECT_ID('dw.vwRptPlanPlantaDia', 'V') IS NOT NULL
    EXEC(N'CREATE OR ALTER VIEW dw.vwRptPlanPlantaDia AS
SELECT
    p.Planta,
    p.Fecha,
    NULLIF(SUM(p.PlanDiarioInversor), 0) AS PlanKwh,
    COUNT(*)                             AS InversoresConPlan
FROM dw.dimPlanGeneracion p
WHERE p.EsVigente = 1
GROUP BY p.Planta, p.Fecha;');
GO
