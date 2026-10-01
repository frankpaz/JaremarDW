-- 245: separa el dominio Compras, igual que Ventas (243/244):
--   * TerminosCompra pasa a su propio dominio (estaba en 'Compras'), para que el monitor de compras
--     acotado a los dominios Compras y Proveedor cubra solo dimProveedor > factCompras.
--   * El proceso 'Compras' (solo guarda el watermark compartido) quedo en 'SinClasificar' porque
--     usp_Etl_WatermarkActualizar no recibe dominio; pasa a 'Compras'.
-- Idempotente. Compatible con SQL Server 2016.

UPDATE dbo.EtlProcess
SET Dominio = 'TerminosCompra', FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre IN ('TerminosCompra', 'TerminosCompra_Silver', 'TerminosCompra_Gold') AND Dominio <> 'TerminosCompra';

UPDATE dbo.EtlProcess
SET Dominio = 'Compras', FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre = 'Compras' AND Dominio = 'SinClasificar';
