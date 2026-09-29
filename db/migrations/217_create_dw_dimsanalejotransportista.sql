-- 217: dw.dimSanAlejoTransportista -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoTransportista.
-- La usan los 3 hechos SanAlejo (via CODCIA + CODTRA).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoTransportista'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoTransportista (
        SanAlejoTransportistaKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoTransportista PRIMARY KEY,
        CodigoEmpresa         INT            NOT NULL,
        CodigoTransportista   INT            NOT NULL,
        NombreTransportista   NVARCHAR(70)   NULL,
        ValorKilometro        DECIMAL(12,4)  NULL,
        Precio                DECIMAL(12,2)  NULL,
        CodigoAlternoLX       INT            NULL,
        EsVigente             BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoTransportista_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)     NOT NULL,
        FechaCargaDw          DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoTransportista_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoTransportista_Codigo UNIQUE (CodigoEmpresa, CodigoTransportista)
    );
END
GO
