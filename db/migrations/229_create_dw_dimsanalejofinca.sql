-- 229: dw.dimSanAlejoFinca -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoFinca.
-- La usan dw.factSanAlejoFruta (via CODCIA + FINCA).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoFinca'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoFinca (
        SanAlejoFincaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoFinca PRIMARY KEY,
        CodigoEmpresa         INT            NOT NULL,
        CodigoFinca           NVARCHAR(5)    NOT NULL,
        CodigoSucursal        INT            NULL,
        FrenteCosecha         NVARCHAR(50)   NULL,
        ExtensionHectareas    DECIMAL(10,3)  NULL,
        DescripcionFinca      NVARCHAR(100)  NULL,
        Variedad              NVARCHAR(50)   NULL,
        PrecioTMFFB           DECIMAL(13,2)  NULL,
        CodigoPlanilla        NVARCHAR(4)    NULL,
        CompaniaRelacionada   INT            NULL,
        Estatus               NVARCHAR(1)    NULL,
        EsVigente             BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoFinca_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)     NOT NULL,
        FechaCargaDw          DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoFinca_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoFinca_Codigo UNIQUE (CodigoEmpresa, CodigoFinca)
    );
END
GO
