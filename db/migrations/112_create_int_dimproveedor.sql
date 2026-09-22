-- 112: [int].dimProveedor -- version Silver de stg.dimProveedor.
-- Fuente: PROLX835F.AVM, VMID='VM' (98.9% de los proveedores en compras,
-- PROLX835F.APL.PLVNDR "Payables Line File", coinciden con esta poblacion,
-- contra ~1% con VMID='VZ' -- ver db/discovery/discover_columnas.py).
-- Llave de negocio VENDOR, unica dentro de VMID='VM' (19789 filas = 19789
-- VENDOR distintos, verificado). Patron FULL + SCD Tipo 1.
-- A diferencia de dimCliente, AVM no tiene columnas de auditoria de
-- creacion/entrada (no existe equivalente a CMDCRT/CMENDT/CMENTM/CMENUS en
-- RCM) -- no hay tiebreak natural para el dedup, se usa (SELECT NULL).
-- VDTLPD (DECIMAL YYYYMMDD) -> DATE.
-- Se preservan los nombres de columna originales del AS400; el renombre a
-- nombre de negocio ocurre solo en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'dimProveedor'
)
BEGIN
    CREATE TABLE [int].dimProveedor (
        VENDOR          DECIMAL(8,0)  NOT NULL CONSTRAINT PK_Int_dimProveedor PRIMARY KEY,
        VNDNAM          NVARCHAR(50)  NULL,
        VNALPH          NVARCHAR(10)  NULL,
        VNDAD1          NVARCHAR(50)  NULL,
        VNDAD2          NVARCHAR(50)  NULL,
        VSTATE          NVARCHAR(3)   NULL,
        VCOUN           NVARCHAR(4)   NULL,
        VTYPE           NVARCHAR(4)   NULL,
        VCMPNY          DECIMAL(2,0)  NULL,
        VTERMS          NVARCHAR(2)   NULL,
        VPAYTO          DECIMAL(8,0)  NULL,
        VCURR           NVARCHAR(3)   NULL,
        VPAYTY          NVARCHAR(1)   NULL,
        V1TIME          NVARCHAR(1)   NULL,
        VCON            NVARCHAR(30)  NULL,
        VPHONE          NVARCHAR(25)  NULL,
        VTAX            NVARCHAR(1)   NULL,
        VTAXCD          NVARCHAR(5)   NULL,
        VMIDNM          NVARCHAR(12)  NULL,
        V1099           NVARCHAR(1)   NULL,
        V1099C          NVARCHAR(9)   NULL,
        VDTLPD          DATE          NULL,
        VPYTYR          DECIMAL(15,2) NULL,
        VDPURS          DECIMAL(15,2) NULL,
        VHOLD           NVARCHAR(1)   NULL,
        VNSTAT          NVARCHAR(1)   NULL,
        VMBANK          NVARCHAR(3)   NULL,
        VMBNKC          NVARCHAR(10)  NULL,
        VMBRNO          NVARCHAR(25)  NULL,
        VMBNKA          NVARCHAR(25)  NULL,
        VMCARR          NVARCHAR(6)   NULL,
        VMMNTR          NVARCHAR(4)   NULL,
        VMLANG          NVARCHAR(3)   NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_dimProveedor_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_dimProveedor_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL
    );
END
GO
