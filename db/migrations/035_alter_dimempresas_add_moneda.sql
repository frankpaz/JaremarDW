-- 035: agrega la moneda funcional a dimEmpresas (Silver y Gold), a partir de
-- PROLX835F.RCO (compania -> moneda, relacion 1:1 confirmada: 63 de 64
-- companias tienen exactamente una moneda; '02' -- una entidad de
-- consolidacion -- no tiene). Aditivo puro, columnas nullable.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[int].dimEmpresas') AND name = 'MonedaFuncional')
    ALTER TABLE [int].dimEmpresas ADD MonedaFuncional NVARCHAR(3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dw.dimEmpresas') AND name = 'CodigoMoneda')
    ALTER TABLE dw.dimEmpresas ADD CodigoMoneda NVARCHAR(3) NULL;
GO
