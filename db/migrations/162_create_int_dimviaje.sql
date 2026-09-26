-- 162: [int].dimViaje -- version Silver de stg.dimViaje (PROLXUSRF.ENVU0A44).
-- Llave de negocio VCODPA (unica en el origen, 300 filas al 2026-09-26).
-- Fechas AAAAMMDD y horas HHMMSS numericas convertidas a DATE/TIME reales
-- (0 -> NULL; la hora queda NULL si su fecha es NULL). Montos y VSTS tal
-- como vienen: VSTS trae E/blanco/A/D/M aunque el origen documenta "A, C".

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimViaje'
)
BEGIN
    CREATE TABLE [int].dimViaje (
        VCODPA          INT           NOT NULL CONSTRAINT PK_Int_dimViaje PRIMARY KEY,
        VDESC           NVARCHAR(40)  NULL,
        VPAGAM          DECIMAL(8,2)  NULL,
        VPAGAA          DECIMAL(8,2)  NULL,
        VUSUAG          NVARCHAR(10)  NULL,
        VFECHG          DATE          NULL,
        VHORAG          TIME(0)       NULL,
        VUSUAM          NVARCHAR(10)  NULL,
        VFECHM          DATE          NULL,
        VHORAM          TIME(0)       NULL,
        VSTS            NVARCHAR(1)   NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimViaje_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimViaje_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO
