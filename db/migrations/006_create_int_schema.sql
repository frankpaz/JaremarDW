-- 006: esquema Silver (int) -- limpieza, deduplicacion, tipado real, conformacion
-- de llaves de negocio entre stg (Bronze) y dw (Gold, pendiente).

-- 'int' es palabra reservada en T-SQL (tipo de dato) -- se referencia siempre
-- entre corchetes ([int].tabla) en todo el proyecto.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'int')
    EXEC('CREATE SCHEMA [int]');
GO
