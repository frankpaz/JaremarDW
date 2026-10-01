-- 244: TerminosVenta y ClasesProducto pasan a su propio dominio (como el resto de las dimensiones), para
-- que el monitor de ventas acotado a los dominios Ventas y Producto cubra solo dimProducto > factVentas.
-- Antes estaban en 'Ventas' y 'Producto'. Idempotente. Compatible con SQL Server 2016.

UPDATE dbo.EtlProcess
SET Dominio = 'TerminosVenta', FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre IN ('TerminosVenta', 'TerminosVenta_Silver', 'TerminosVenta_Gold') AND Dominio <> 'TerminosVenta';

UPDATE dbo.EtlProcess
SET Dominio = 'ClasesProducto', FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre IN ('ClasesProducto', 'ClasesProducto_Silver', 'ClasesProducto_Gold') AND Dominio <> 'ClasesProducto';
