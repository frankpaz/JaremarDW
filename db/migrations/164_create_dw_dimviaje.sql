-- 164: dw.dimViaje -- dimension Gold (SCD Tipo 1), a partir de [int].dimViaje.
-- Nombres de negocio tomados de COLUMN_TEXT del origen. EstatusViaje sin
-- decodificar: los valores reales (E/A/D/M/NULL) no coinciden con lo
-- documentado ("A, C") y su significado no esta confirmado.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimViaje'
)
BEGIN
    CREATE TABLE dw.dimViaje (
        ViajeKey               INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimViaje PRIMARY KEY,
        CodigoViaje            INT           NOT NULL,
        DescripcionViaje       NVARCHAR(40)  NULL,
        ValorPagarMotorista    DECIMAL(8,2)  NULL,
        ValorPagarAyudante     DECIMAL(8,2)  NULL,
        UsuarioCreacion        NVARCHAR(10)  NULL,
        FechaCreacion          DATE          NULL,
        HoraCreacion           TIME(0)       NULL,
        UsuarioModificacion    NVARCHAR(10)  NULL,
        FechaModificacion      DATE          NULL,
        HoraModificacion       TIME(0)       NULL,
        EstatusViaje           NVARCHAR(1)   NULL,
        EsVigente              BIT           NOT NULL CONSTRAINT DF_dw_dimViaje_EsVigente DEFAULT (1),
        HashDiff               BINARY(32)    NOT NULL,
        FechaCargaDw           DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimViaje_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                  INT           NULL,
        CONSTRAINT UQ_dw_dimViaje_CodigoViaje UNIQUE (CodigoViaje)
    );
END
GO
