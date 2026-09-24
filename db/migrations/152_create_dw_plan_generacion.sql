-- 152: Gold (dw) del plan de generacion de energia.
-- dw.dimPlanGeneracion: plan de energia (kWh) por dia de cada inversor, con
-- historial de versiones; EsVigente marca la version en uso para cada fecha e
-- inversor. CodigoInversor es el ID del Excel (HARINA-1, JABON-3, ...).
-- SmaDeviceKey y DeviceCapacityKey enlazan el inversor con las dimensiones de
-- dispositivos (dw.dimSmaDevices y dw.dimDeviceCapacity); quedan NULL si el ID
-- no resuelve en ninguna (sin FK real, para tolerar inversores aun no dados de
-- alta -- mismo criterio que los hechos Solar). Los resumenes por PI y por
-- plantel se calculan en las vistas de la migracion 154.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimPlanGeneracion'
)
BEGIN
    CREATE TABLE dw.dimPlanGeneracion (
        PlanKey            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimPlanGeneracion PRIMARY KEY,
        Fecha               DATE           NOT NULL,
        CodigoInversor      NVARCHAR(50)   NOT NULL,
        SmaDeviceKey        INT            NULL,
        DeviceCapacityKey   INT            NULL,
        PlanKwh             DECIMAL(18,8)  NOT NULL,
        PlanVersion         NVARCHAR(50)   NOT NULL,
        PlanFuente          NVARCHAR(100)  NOT NULL,
        ArchivoOrigen       NVARCHAR(260)  NULL,
        EsVigente           BIT            NOT NULL CONSTRAINT DF_dw_dimPlanGeneracion_EsVigente DEFAULT (1),
        HashDiff            BINARY(32)     NOT NULL,
        FechaCargaDw        DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimPlanGeneracion_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId               INT            NULL,
        CONSTRAINT UQ_dw_dimPlanGeneracion UNIQUE (Fecha, CodigoInversor, PlanVersion)
    );
    CREATE INDEX IX_dw_dimPlanGeneracion_SmaDeviceKey ON dw.dimPlanGeneracion (SmaDeviceKey);
    CREATE INDEX IX_dw_dimPlanGeneracion_Vigente ON dw.dimPlanGeneracion (EsVigente, Fecha);
END
GO
