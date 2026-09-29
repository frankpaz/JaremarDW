-- 225: dw.dimSanAlejoProductor -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoProductor.
-- La usan dw.factSanAlejoFruta (via CODCIA + CODPRO; finca 98 = productores independientes).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoProductor'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoProductor (
        SanAlejoProductorKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoProductor PRIMARY KEY,
        CodigoEmpresa         INT            NOT NULL,
        CodigoProductor       INT            NOT NULL,
        NombreProductor       NVARCHAR(80)   NULL,
        UbicacionFinca        NVARCHAR(150)  NULL,
        Sector                NVARCHAR(4)    NULL,
        Estado                INT            NULL,
        TotalHectareas        DECIMAL(10,3)  NULL,
        NumeroContrato        BIGINT         NULL,
        FechaInicioContrato   DATE           NULL,
        FechaFinContrato      DATE           NULL,
        CodigoLocalizacion    INT            NULL,
        CodigoAnterior        INT            NULL,
        EsVigente             BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoProductor_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)     NOT NULL,
        FechaCargaDw          DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoProductor_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoProductor_Codigo UNIQUE (CodigoEmpresa, CodigoProductor)
    );
END
GO
