-- 265: [int].dimAlmacen -- version Silver de stg.dimAlmacen (PROLX835F.IWM,
-- "Warehouse Master"). Llave de negocio LWHS, unica entre las dos poblaciones
-- de LID ('WM' activos y 'WZ' dados de baja; ambas se cargan). Nombres crudos
-- del AS400; fechas AAAAMMDD -> DATE y horas HHMMSS -> TIME (0 = NULL).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimAlmacen'
)
BEGIN
    CREATE TABLE [int].dimAlmacen (
        LWHS            NVARCHAR(3)    NOT NULL CONSTRAINT PK_Int_dimAlmacen PRIMARY KEY,
        LID             NVARCHAR(2)    NULL,
        LDESC           NVARCHAR(30)   NULL,
        LLDTE           DATE           NULL,
        LADD1           NVARCHAR(50)   NULL,
        LADD2           NVARCHAR(50)   NULL,
        LADD3           NVARCHAR(50)   NULL,
        LCOUN           NVARCHAR(4)    NULL,
        LPHON           NVARCHAR(25)   NULL,
        LALWH           NVARCHAR(1)    NULL,
        LPOAS           NVARCHAR(9)    NULL,
        LNETW           NVARCHAR(1)    NULL,
        WMCOMP          DECIMAL(2,0)   NULL,
        WMNCST          NVARCHAR(1)    NULL,
        LFRFG           NVARCHAR(1)    NULL,
        WMFAC           NVARCHAR(3)    NULL,
        WMDYP           DECIMAL(3,0)   NULL,
        WMDYM           DECIMAL(3,0)   NULL,
        WMTYP           DECIMAL(4,1)   NULL,
        WMTYM           DECIMAL(4,1)   NULL,
        WMAUTO          NVARCHAR(1)    NULL,
        WMRLOC          NVARCHAR(10)   NULL,
        WMLUSR          NVARCHAR(10)   NULL,
        WFLDTE          DATE           NULL,
        WFLTME          TIME(0)        NULL,
        WMFAXN          NVARCHAR(25)   NULL,
        WMCBY           NVARCHAR(10)   NULL,
        WMCDT           DATE           NULL,
        WMCTM           TIME(0)        NULL,
        WMSTE           NVARCHAR(3)    NULL,
        WMSLOC          NVARCHAR(10)   NULL,
        WMLANG          NVARCHAR(3)    NULL,
        WMMNWH          DECIMAL(1,0)   NULL,
        WMALRQ          DECIMAL(1,0)   NULL,
        EsVigente       BIT            NOT NULL CONSTRAINT DF_Int_dimAlmacen_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)     NOT NULL,
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_dimAlmacen_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL
    );
END
GO
