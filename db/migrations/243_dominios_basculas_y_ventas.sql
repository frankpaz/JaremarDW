-- 243: reclasifica dominios en dbo.EtlProcess para que el monitor se pueda acotar por dominio.
--   * Los 5 pipelines de bascula (dimBascula, dimTipoBoleta, dimLugarBascula, dimProductoBascula,
--     factBasculaBufalo) pasan de 'Bascula' a 'Basculas' (los scripts ya registran 'Basculas').
--   * El proceso 'Ventas' (solo guarda el watermark compartido) quedo en 'SinClasificar' porque
--     usp_Etl_WatermarkActualizar no recibe dominio; pasa a 'Ventas'.
-- Idempotente. Compatible con SQL Server 2016.

UPDATE dbo.EtlProcess
SET Dominio = 'Basculas', FechaModificacion = SYSDATETIME()
WHERE Dominio = 'Bascula';

UPDATE dbo.EtlProcess
SET Dominio = 'Ventas', FechaModificacion = SYSDATETIME()
WHERE ProcesoNombre = 'Ventas' AND Dominio = 'SinClasificar';
