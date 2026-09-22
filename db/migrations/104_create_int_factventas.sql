-- 104: [int].factVentas -- Silver de stg.factVentasLineas (PROLX835F.SIL,
-- ILID='IL') enriquecido con stg.factVentasEncabezados (PROLX835F.SIH,
-- SIID='IH'). Grano: una fila por linea de factura (llave de negocio
-- ILCOMP+ILDPFX+ILDOCN+ILDYR+ILDTYP+ILLINE, verificado casi unico:
-- 1546520 distintos de 1546529 filas). Patron FULL + SCD Tipo 1 (SIL/SIH
-- son tablas vivas del ERP con ~4.5 meses de ventana, sin columna confiable
-- de ultima modificacion), igual que factEnvios.
-- ILDATE/ILSDTE/IHENDT (DECIMAL YYYYMMDD) -> DATE. IHENTM (DECIMAL HHMMSS)
-- -> TIME(0).
-- ILPCST (etiquetado "Proof of Delivery Cost" en el origen) se mantiene con
-- su nombre AS400 crudo: los datos sugieren que en realidad es el costo de
-- la linea (correlaciona con SICST de SIH), pero no esta confirmado con el
-- equipo de datos -- no se renombra hasta confirmar.
-- Las columnas de SIH (SICURR, SICNFC, SIGCNV, SITERM, SICARR, SIROUT,
-- IHENDT, IHENTM, IHENUS) no tienen diccionario de campos confirmado (a
-- diferencia de las de SIL) -- se mantienen con su nombre AS400 crudo
-- tambien en dw.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factVentas'
)
BEGIN
    CREATE TABLE [int].factVentas (
        ILCOMP    DECIMAL(2,0)     NOT NULL,
        ILDPFX    NVARCHAR(2)      NOT NULL,
        ILDOCN    DECIMAL(8,0)     NOT NULL,
        ILDYR     DECIMAL(2,0)     NOT NULL,
        ILDTYP    DECIMAL(1,0)     NOT NULL,
        ILLINE    DECIMAL(4,0)     NOT NULL,
        ILSEQ     DECIMAL(4,0)     NULL,
        ILINVN    DECIMAL(8,0)     NULL,
        ILORD     DECIMAL(8,0)     NULL,
        ILDATE    DATE             NULL,
        ILSDTE    DATE             NULL,
        ILPROD    NVARCHAR(35)     NULL,
        ILCUST    DECIMAL(8,0)     NULL,
        ILCUSB    DECIMAL(8,0)     NULL,
        ILWHS     NVARCHAR(3)      NULL,
        ILLTYP    NVARCHAR(1)      NULL,
        ILOCLS    DECIMAL(3,0)     NULL,
        ILQTY     DECIMAL(11,3)    NULL,
        ILQINS    DECIMAL(11,3)    NULL,
        ILNET     DECIMAL(19,7)    NULL,
        ILNETS    DECIMAL(19,7)    NULL,
        ILLIST    DECIMAL(14,4)    NULL,
        ILBLST    DECIMAL(14,4)    NULL,
        ILEXTA    DECIMAL(15,2)    NULL,
        ILREV     DECIMAL(15,2)    NULL,
        ILPCST    DECIMAL(15,5)    NULL,
        ILUM      NVARCHAR(2)      NULL,
        ILSLUM    NVARCHAR(2)      NULL,
        ILCWUM    NVARCHAR(2)      NULL,
        ILTR01    NVARCHAR(5)      NULL,
        ILTA01    DECIMAL(17,4)    NULL,
        ILTR02    NVARCHAR(5)      NULL,
        ILTA02    DECIMAL(17,4)    NULL,
        ILSAL1    DECIMAL(6,0)     NULL,
        ILSAL3    DECIMAL(6,0)     NULL,
        ILCCOM    NVARCHAR(2)      NULL,
        ILCPO     NVARCHAR(23)     NULL,
        ILCONS    DECIMAL(6,0)     NULL,
        ILNPSC    NVARCHAR(2)      NULL,
        ILLPSC    NVARCHAR(2)      NULL,
        ILPFAC    NVARCHAR(3)      NULL,
        ILPKGG    DECIMAL(8,0)     NULL,
        SICURR    NVARCHAR(3)      NULL,
        SICNFC    DECIMAL(15,7)    NULL,
        SIGCNV    DECIMAL(15,7)    NULL,
        SITERM    NVARCHAR(2)      NULL,
        SICARR    NVARCHAR(6)      NULL,
        SIROUT    NVARCHAR(6)      NULL,
        IHENDT    DATE             NULL,
        IHENTM    TIME(0)          NULL,
        IHENUS    NVARCHAR(10)     NULL,
        EsVigente       BIT           NOT NULL CONSTRAINT DF_Int_factVentas_EsVigente DEFAULT (1),
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_factVentas_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT PK_Int_factVentas PRIMARY KEY (ILCOMP, ILDPFX, ILDOCN, ILDYR, ILDTYP, ILLINE)
    );
END
GO
