-- 209: dw.dimSanAlejoProducto -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoProducto.
-- La usan los 3 hechos SanAlejo (via TIPOP).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoProducto'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoProducto (
        SanAlejoProductoKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoProducto PRIMARY KEY,
        CodigoProducto    NVARCHAR(5)    NOT NULL,
        NombreProducto    NVARCHAR(100)  NULL,
        CodigoAlternoLX   NVARCHAR(35)   NULL,
        UnidadMedida      NVARCHAR(3)    NULL,
        PrecioProducto    DECIMAL(15,4)  NULL,
        CertificadoRSPO   NVARCHAR(20)   NULL,
        EsVigente         BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoProducto_EsVigente DEFAULT (1),
        HashDiff          BINARY(32)     NOT NULL,
        FechaCargaDw      DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoProducto_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId             INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoProducto_Codigo UNIQUE (CodigoProducto)
    );
END
GO
