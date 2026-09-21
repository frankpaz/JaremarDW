-- 017: dw.dimEmpresas -- dimension Gold (SCD Tipo 1), a partir de [int].dimEmpresas.
-- CodigoEmpresa/RazonSocial con confianza razonable por el contenido de los
-- datos (nombres legales de compania). FechaRegistro/HoraRegistro son un
-- supuesto (fecha/hora del registro en el AS400), sin confirmar.
-- SVID se mantiene con su nombre original -- solo tiene 2 valores (SV/SZ) y
-- no hay ninguna base para asignarle un nombre de negocio con confianza.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimEmpresas'
)
BEGIN
    CREATE TABLE dw.dimEmpresas (
        EmpresaKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimEmpresas PRIMARY KEY,
        CodigoEmpresa         NVARCHAR(16)  NOT NULL,
        SVID                  NVARCHAR(2)   NULL,
        RazonSocial           NVARCHAR(30)  NULL,
        FechaRegistro         DATE          NULL,
        HoraRegistro          TIME(0)       NULL,
        EsVigente             BIT           NOT NULL CONSTRAINT DF_dw_dimEmpresas_EsVigente DEFAULT (1),
        HashDiff              BINARY(32)    NOT NULL,
        FechaCargaDw          DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimEmpresas_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                 INT           NULL,
        CONSTRAINT UQ_dw_dimEmpresas_CodigoEmpresa UNIQUE (CodigoEmpresa)
    );
END
GO
