-- 002: extiende ETL_Control y ETL_Log de forma aditiva (sin tocar columnas existentes)
-- dw.usp_MergeBascula y dw.usp_MergeProducto escriben directo a ETL_Log por nombre de
-- columna -- por eso este script SOLO agrega, nunca renombra ni elimina.

-- ETL_Control: enlace al catálogo de procesos
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ETL_Control') AND name = 'ProcesoId')
    ALTER TABLE dbo.ETL_Control ADD ProcesoId INT NULL;
GO

UPDATE c
SET c.ProcesoId = p.ProcesoId
FROM dbo.ETL_Control c
JOIN dbo.EtlProcess p ON p.ProcesoNombre = c.Proceso
WHERE c.ProcesoId IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EtlControl_EtlProcess')
    ALTER TABLE dbo.ETL_Control ADD CONSTRAINT FK_EtlControl_EtlProcess FOREIGN KEY (ProcesoId) REFERENCES dbo.EtlProcess(ProcesoId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.ETL_Control') AND name = 'UQ_ETL_Control_Proceso')
    CREATE UNIQUE INDEX UQ_ETL_Control_Proceso ON dbo.ETL_Control(Proceso);
GO

-- ETL_Log: enlace al catálogo, validación de Estado, duración calculada
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ETL_Log') AND name = 'ProcesoId')
    ALTER TABLE dbo.ETL_Log ADD ProcesoId INT NULL;
GO

UPDATE l
SET l.ProcesoId = p.ProcesoId
FROM dbo.ETL_Log l
JOIN dbo.EtlProcess p ON p.ProcesoNombre = l.Proceso
WHERE l.ProcesoId IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EtlLog_EtlProcess')
    ALTER TABLE dbo.ETL_Log ADD CONSTRAINT FK_EtlLog_EtlProcess FOREIGN KEY (ProcesoId) REFERENCES dbo.EtlProcess(ProcesoId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_EtlLog_Estado')
    ALTER TABLE dbo.ETL_Log ADD CONSTRAINT CK_EtlLog_Estado CHECK (Estado IN ('EN PROCESO','EXITO','ERROR'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.ETL_Log') AND name = 'DuracionSegundos')
    ALTER TABLE dbo.ETL_Log ADD DuracionSegundos AS (DATEDIFF(SECOND, FechaInicio, FechaFin)) PERSISTED;
GO
