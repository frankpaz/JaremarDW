-- 108: [int].dimCliente -- version Silver de stg.dimCliente.
-- Fuente: PROLX835F.RCM, CMID='CM' (98.3% de los clientes en dw.factVentas
-- coinciden con esta poblacion, contra 1.7% con CMID='CZ' -- ver
-- db/discovery/discover_columnas.py). Llave de negocio CCUST, unica dentro
-- de CMID='CM' (33740 filas = 33740 CCUST distintos, verificado). Patron
-- FULL + SCD Tipo 1 (igual que dimSector/dimEmpresas).
-- CLAST/CLPDT/CMDCRT/CMENDT/CLDTE (DECIMAL YYYYMMDD) -> DATE.
-- CMENTM/CLTME (DECIMAL HHMMSS) -> TIME(0).
-- Se preservan los nombres de columna originales del AS400; el renombre a
-- nombre de negocio ocurre solo en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimCliente'
)
BEGIN
    CREATE TABLE [int].dimCliente (
        CCUST           DECIMAL(8,0)  NOT NULL CONSTRAINT PK_Int_dimCliente PRIMARY KEY,
        CNME            NVARCHAR(50)  NULL,
        CMALPH          NVARCHAR(20)  NULL,
        CAD1            NVARCHAR(50)  NULL,
        CAD2            NVARCHAR(50)  NULL,
        CAD3            NVARCHAR(50)  NULL,
        CSTE            NVARCHAR(3)   NULL,
        CZIP            NVARCHAR(9)   NULL,
        CCOUN           NVARCHAR(4)   NULL,
        CTYPE           NVARCHAR(4)   NULL,
        CCOMP           DECIMAL(2,0)  NULL,
        CCCUS           DECIMAL(8,0)  NULL,
        CREG            NVARCHAR(6)   NULL,
        CMPREG          NVARCHAR(6)   NULL,
        CDEA1           NVARCHAR(8)   NULL,
        CSAL            DECIMAL(6,0)  NULL,
        CTERM           NVARCHAR(2)   NULL,
        CTAX            NVARCHAR(5)   NULL,
        CTXID           NVARCHAR(12)  NULL,
        CPCD            NVARCHAR(1)   NULL,
        CCURR           NVARCHAR(3)   NULL,
        CWHSE           NVARCHAR(3)   NULL,
        CROUT           NVARCHAR(6)   NULL,
        CMDFOT          NVARCHAR(1)   NULL,
        CCON            NVARCHAR(30)  NULL,
        CPHON           NVARCHAR(25)  NULL,
        CRDOL           DECIMAL(15,2) NULL,
        CDLIM           DECIMAL(3,0)  NULL,
        CAPD            DECIMAL(3,0)  NULL,
        CAIS            DECIMAL(15,2) NULL,
        CLAST           DATE          NULL,
        CLPDT           DATE          NULL,
        CLPAM           DECIMAL(15,2) NULL,
        CMHOLD          NVARCHAR(1)   NULL,
        CMDCRT          DATE          NULL,
        CMENDT          DATE          NULL,
        CMENTM          TIME(0)       NULL,
        CMENUS          NVARCHAR(10)  NULL,
        CLDTE           DATE          NULL,
        CLTME           TIME(0)       NULL,
        CLUSR           NVARCHAR(10)  NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimCliente_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimCliente_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO
