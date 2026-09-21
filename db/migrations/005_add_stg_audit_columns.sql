-- 005: columnas de auditoría/trazabilidad en stg (Fase 2 -- formalizar Bronze)
-- Alcance: solo dimProducto y factMovimientosBascula (dominio no-solar). No se
-- toca ninguna tabla del dominio solar. Aditivo puro: columnas nullable al final,
-- no se renombra ni se quita nada existente.
--
-- RunId queda sin FK hacia dbo.EtlRunLog a propósito: el loader actual (Python,
-- fuera de nuestro control) todavía no llama al framework de control, así que
-- forzar la integridad referencial aquí rompería la carga real. Se agrega la
-- columna para que, cuando el loader empiece a usar dbo.usp_Etl_RunIniciar, quede
-- lista para poblarse -- la FK se puede agregar después cuando eso pase.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stg.dimProducto') AND name = 'FechaCargaStg')
    ALTER TABLE stg.dimProducto ADD FechaCargaStg DATETIME2(7) NOT NULL CONSTRAINT DF_dimProducto_FechaCargaStg DEFAULT (SYSDATETIME());
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stg.dimProducto') AND name = 'RunId')
    ALTER TABLE stg.dimProducto ADD RunId INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stg.factMovimientosBascula') AND name = 'FechaCargaStg')
    ALTER TABLE stg.factMovimientosBascula ADD FechaCargaStg DATETIME2(7) NOT NULL CONSTRAINT DF_factMovimientosBascula_FechaCargaStg DEFAULT (SYSDATETIME());
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('stg.factMovimientosBascula') AND name = 'RunId')
    ALTER TABLE stg.factMovimientosBascula ADD RunId INT NULL;
GO
