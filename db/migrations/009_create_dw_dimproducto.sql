-- 009: dw.dimProducto -- dimension Gold (SCD Tipo 1), a partir de [int].dimProducto.
-- Nombres de negocio: ClaseItem, UMAlmacen, UMCompra confirmados por precedente
-- (aparecian con esos nombres en el usp_MergeProducto original, visto en la Fase 0).
-- FechaUltimaTransaccion/FechaUltimaModificacion/HoraUltimaModificacion son un
-- supuesto razonable (convencion AS400/JDE: LDTE = last date, MMNDT/MMNTM =
-- maintenance date/time) -- sin diccionario de datos que lo confirme, pendiente
-- de validar con el equipo de datos.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimProducto'
)
BEGIN
    CREATE TABLE dw.dimProducto (
        ProductoKey                INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimProducto PRIMARY KEY,
        CodigoProducto              NVARCHAR(70)  NOT NULL,
        Descripcion                 NVARCHAR(100) NULL,
        ClaseItem                   NVARCHAR(4)   NULL,
        UMAlmacen                   NVARCHAR(4)   NULL,
        UMCompra                    NVARCHAR(4)   NULL,
        FechaUltimaTransaccion      DATE          NULL,
        FechaUltimaModificacion     DATE          NULL,
        HoraUltimaModificacion      TIME(0)       NULL,
        EsVigente                   BIT           NOT NULL CONSTRAINT DF_dw_dimProducto_EsVigente DEFAULT (1),
        HashDiff                    BINARY(32)    NOT NULL,
        FechaCargaDw                DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimProducto_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                       INT           NULL,
        CONSTRAINT UQ_dw_dimProducto_CodigoProducto UNIQUE (CodigoProducto)
    );
END
GO
