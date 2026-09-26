-- 166: dimViaje solo con los viajes de codigo >= 8000 (8000-9999), los que se
-- usan para relacionar con envios (regla de negocio del usuario, 2026-09-26).
-- El extract ya filtra en el origen; esta migracion quita las filas < 8000
-- que quedaron de la carga inicial (sin esto el merge silver solo las marcaria
-- EsVigente = 0). La relacion con factEnvios se construira mas adelante (no
-- es ENCROU directo). Idempotente.

DELETE FROM dw.dimViaje WHERE CodigoViaje < 8000;
DELETE FROM [int].dimViaje WHERE VCODPA < 8000;
GO
