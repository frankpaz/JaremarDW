-- 167: [int].dimVehiculo -- version Silver de stg.dimVehiculo (PROLX835F.LCM).
-- Cada registro es un vehiculo (el origen lo llama "Freight Carrier"). Llave
-- de negocio CMCARR, unica entre las dos poblaciones de CMID ('CM' y 'CZ',
-- ambas se cargan). Nombres crudos del AS400; varias columnas guardan otro
-- dato que el de su descripcion (ver 169). CMLDTE/CMLTME numericas -> DATE/TIME.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimVehiculo'
)
BEGIN
    CREATE TABLE [int].dimVehiculo (
        CMCARR          NVARCHAR(6)    NOT NULL CONSTRAINT PK_Int_dimVehiculo PRIMARY KEY,
        CMID            NVARCHAR(2)    NULL,
        CMCDES          NVARCHAR(30)   NULL,
        CMXDES          NVARCHAR(50)   NULL,
        CMADR1          NVARCHAR(50)   NULL,
        CMADR2          NVARCHAR(50)   NULL,
        CMSTCD          NVARCHAR(3)    NULL,
        CMPSCD          NVARCHAR(10)   NULL,
        CMCNTY          NVARCHAR(4)    NULL,
        CMSHPC          DECIMAL(15,2)  NULL,
        CMPERR          DECIMAL(1,0)   NULL,
        CMVEND          DECIMAL(8,0)   NULL,
        CMINVF          NVARCHAR(1)    NULL,
        CMLUSR          NVARCHAR(10)   NULL,
        CMLDTE          DATE           NULL,
        CMLTME          TIME(0)        NULL,
        CMADR5          NVARCHAR(50)   NULL,
        CMADR6          NVARCHAR(50)   NULL,
        CMATTN          NVARCHAR(30)   NULL,
        CMDATN          NVARCHAR(50)   NULL,
        CMPHON          NVARCHAR(25)   NULL,
        CMFRCC          NVARCHAR(2)    NULL,
        EsVigente       BIT            NOT NULL CONSTRAINT DF_Int_dimVehiculo_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)     NOT NULL,
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimVehiculo_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL
    );
END
GO
