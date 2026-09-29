-- 213: dw.dimSanAlejoLocalizacion -- dimension Gold (SCD Tipo 1) del dominio SanAlejo, a partir de [int].dimSanAlejoLocalizacion.
-- La usan los 3 hechos SanAlejo (via CODCIA + CODLOC).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimSanAlejoLocalizacion'
)
BEGIN
    CREATE TABLE dw.dimSanAlejoLocalizacion (
        SanAlejoLocalizacionKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimSanAlejoLocalizacion PRIMARY KEY,
        CodigoEmpresa        INT            NOT NULL,
        CodigoLocalizacion   INT            NOT NULL,
        Origen               NVARCHAR(80)   NULL,
        Destino              NVARCHAR(80)   NULL,
        PrecioTM             DECIMAL(13,4)  NULL,
        CostoLibra           DECIMAL(13,4)  NULL,
        CodigoTarifaLX       NVARCHAR(30)   NULL,
        Sector               NVARCHAR(4)    NULL,
        Campo1               NVARCHAR(30)   NULL,
        MarcaEliminado       NVARCHAR(1)    NULL,
        EsVigente            BIT            NOT NULL CONSTRAINT DF_dw_dimSanAlejoLocalizacion_EsVigente DEFAULT (1),
        HashDiff             BINARY(32)     NOT NULL,
        FechaCargaDw         DATETIME2(7)   NOT NULL CONSTRAINT DF_dw_dimSanAlejoLocalizacion_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                INT            NULL,
        CONSTRAINT UQ_dw_dimSanAlejoLocalizacion_Codigo UNIQUE (CodigoEmpresa, CodigoLocalizacion)
    );
END
GO
