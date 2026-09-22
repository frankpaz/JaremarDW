-- 116: [int].factCompras -- Silver de stg.factComprasLineas (PROLX835F.APL,
-- PLID='PL') enriquecido con stg.factComprasEncabezados (PROLX835F.APH,
-- APHID='PH'). Grano: una fila por linea de factura de proveedor (llave de
-- negocio PLCMPY+PLDCPX+PLDCYR+PLDCSQ+PLLINE, casi unica: 714415 distintos
-- de 715323 filas -- se dedup por PLEDTE/PLETIM DESC).
-- INCREMENTAL desde el arranque (a diferencia de factVentas, que empezo
-- FULL y migro despues): APH/APL tienen historia completa desde 2004 (no
-- una ventana viva como SIL/SIH), y el campo de auditoria confiable
-- (PLEDTE = "Created On Date") vive en la LINEA (APL), al reves que en
-- Ventas donde vivia en el encabezado (SIH.IHENDT).
-- PLGLDT/PLEDTE/AINVDT/ADUEDT/ADISCD (DECIMAL YYYYMMDD) -> DATE.
-- PLETIM (DECIMAL HHMMSS) -> TIME(0).
-- El join encabezado-linea NO es 1:1 completo: 104205 encabezados (13%) no
-- tienen linea porque el ERP purga el detalle contable de facturas viejas
-- ya pagadas/cerradas, conservando solo el encabezado -- decision del
-- usuario (2026-09-22) de igual forma priorizar el grano de linea (replica
-- el patron de factVentas) y aceptar perder ese 13% de historico sin
-- detalle de linea.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factCompras'
)
BEGIN
    CREATE TABLE [int].factCompras (
        PLCMPY    DECIMAL(2,0)     NOT NULL,
        PLDCPX    NVARCHAR(2)      NOT NULL,
        PLDCYR    DECIMAL(2,0)     NOT NULL,
        PLDCSQ    DECIMAL(8,0)     NOT NULL,
        PLLINE    DECIMAL(4,0)     NOT NULL,
        PLVNDR    DECIMAL(8,0)     NULL,
        PLINV     NVARCHAR(10)     NULL,
        PLTYPE    NVARCHAR(1)      NULL,
        PLGLDT    DATE             NULL,
        PLAMT     DECIMAL(15,2)    NULL,
        PLBAMT    DECIMAL(15,2)    NULL,
        PLDESC    NVARCHAR(25)     NULL,
        PLUSER    NVARCHAR(10)     NULL,
        PLEDTE    DATE             NULL,
        PLETIM    TIME(0)          NULL,
        PLRESN    NVARCHAR(5)      NULL,
        APHPND    DECIMAL(8,0)     NULL,
        APHBNK    NVARCHAR(3)      NULL,
        APHCUR    NVARCHAR(3)      NULL,
        APHOLD    NVARCHAR(1)      NULL,
        AINVDT    DATE             NULL,
        ADUEDT    DATE             NULL,
        ADISCD    DATE             NULL,
        APCINA    DECIMAL(15,2)    NULL,
        APCAMP    DECIMAL(15,2)    NULL,
        APCOUT    DECIMAL(15,2)    NULL,
        APPORD    DECIMAL(8,0)     NULL,
        APTERM    NVARCHAR(2)      NULL,
        APSTAT    NVARCHAR(1)      NULL,
        APPAYS    NVARCHAR(1)      NULL,
        PHHTRT    DECIMAL(7,4)     NULL,
        PHTXBA    DECIMAL(15,2)    NULL,
        APVNTX    NVARCHAR(5)      NULL,
        APPAYT    NVARCHAR(1)      NULL,
        HashDiff        BINARY(32)    NOT NULL,
        FechaCargaInt   DATETIME2(7)  NOT NULL CONSTRAINT DF_Int_factCompras_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT           NULL,
        CONSTRAINT PK_Int_factCompras PRIMARY KEY (PLCMPY, PLDCPX, PLDCYR, PLDCSQ, PLLINE)
    );
END
GO
