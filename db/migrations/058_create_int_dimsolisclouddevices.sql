-- 058: [int].dimSoliscloudDevices -- version Silver de stg.dimSoliscloudDevices
-- (dominio Solar). Llave de negocio DeviceId (nvarchar, unico y sin nulos en
-- la practica). StationId se preserva como atributo/FK logica hacia
-- dimSoliscloudStations; el join a la llave subrogada de
-- dw.dimSoliscloudStations ocurre en la capa Gold.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimSoliscloudDevices'
)
BEGIN
    CREATE TABLE [int].dimSoliscloudDevices (
        DeviceId                 NVARCHAR(200) NOT NULL CONSTRAINT PK_Int_dimSoliscloudDevices PRIMARY KEY,
        StationId                NVARCHAR(200) NOT NULL,
        DeviceSn                 NVARCHAR(400) NULL,
        Model                    NVARCHAR(400) NULL,
        ProductModel             NVARCHAR(400) NULL,
        CollectorSn              NVARCHAR(400) NULL,
        InverterSoftwareVersion  NVARCHAR(200) NULL,
        TimeZone                 DECIMAL(5,2)  NULL,
        IsGenerator              BIT           NOT NULL,
        EsVigente                BIT           NOT NULL CONSTRAINT DF_Int_dimSoliscloudDevices_EsVigente DEFAULT (1),
        HashDiff                 BINARY(32)    NOT NULL,
        FechaCargaInt            DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimSoliscloudDevices_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId                    INT           NULL
    );
END
GO
