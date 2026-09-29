-- 221: dw.dimSanAlejoCliente -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoCliente.
-- La usan despachos e ingresos SanAlejo (via CODCIA + CODCLI).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoCliente'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoCliente (
        SanAlejoClienteKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoCliente PRIMARY KEY,
        CodigoEmpresa      INT            NOT NULL,
        CodigoCliente      INT            NOT NULL,
        NombreCliente      NVARCHAR(80)   NULL,
        DireccionCliente   NVARCHAR(80)   NULL,
        EsVigente          BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoCliente_EsVigente DEFAULT (1),
        HashDiff           BINARY(32)     NOT NULL,
        FechaCargaDw       DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoCliente_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId              INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoCliente_Codigo UNIQUE (CodigoEmpresa, CodigoCliente)
    );
END
GO
