-- 270: [int].dimUbicacion -- version Silver de stg.dimUbicacion (PROLX835F.ILM,
-- "Location Master"). Una fila por ubicacion dentro de un almacen: llave de negocio
-- WWHS + WLOC, unica entre las dos poblaciones de WID ('WL' activas y 'WZ' dadas de
-- baja; ambas se cargan). Nombres crudos del AS400. La ubicacion en blanco del
-- almacen ZM3 es un registro real del origen y se guarda con WLOC vacio.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimUbicacion'
)
BEGIN
    CREATE TABLE [int].dimUbicacion (
        WWHS            NVARCHAR(3)    NOT NULL,
        WLOC            NVARCHAR(10)   NOT NULL,
        WID             NVARCHAR(2)    NULL,
        WDESC           NVARCHAR(30)   NULL,
        WCYCI           DECIMAL(3,0)   NULL,
        LMPRF           NVARCHAR(10)   NULL,
        WLTYP           NVARCHAR(1)    NULL,
        WZONE           NVARCHAR(3)    NULL,
        WCONC           DECIMAL(11,2)  NULL,
        WALLC           NVARCHAR(1)    NULL,
        WFLOC           NVARCHAR(1)    NULL,
        EsVigente       BIT            NOT NULL CONSTRAINT DF_Int_dimUbicacion_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)     NOT NULL,
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimUbicacion_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL,
        CONSTRAINT PK_Int_dimUbicacion PRIMARY KEY (WWHS, WLOC)
    );
END
GO
