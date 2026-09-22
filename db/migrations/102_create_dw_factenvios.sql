-- 102: dw.factEnvios -- fact Gold (SCD Tipo 1: una fila = estado actual del
-- envio), a partir de [int].factEnvios. Nombres de negocio segun diccionario
-- de campos confirmado por el usuario (2026-09-22):
--   ENCENV=NumeroEnvio, ENCUSU=UsuarioGenero, ENCDSP=PantallaGeneracion,
--   ENCFEC=FechaGeneracion, ENCTIM=HoraGeneracion, ENCCAM=NumeroCamion,
--   ENCPEC=CapacidadCamionKgs, ENCCAD=PropietarioCamion,
--   ENCEMT=NumeroMotorista, ENCEMN=NombreMotorista,
--   ENCEN1-4/ENCED1-4=Numero/NombreEmpleado1-4, ENCROU=CodigoRuta,
--   ENCDER=DescripcionRuta, ENCFEU=FechaUltimaModificacion,
--   ENCTIU=HoraUltimaModificacion, ENCSTA=EstatusEnvio,
--   ENCPES=PesoTotalEnvio, ENCPLA=NumeroPlaca, ENCDT1=Dato1, ENCPT2=Dato2.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'factEnvios'
)
BEGIN
    CREATE TABLE dw.factEnvios (
        EnvioKey                  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_factEnvios PRIMARY KEY,
        NumeroEnvio               DECIMAL(8,0)  NOT NULL,
        UsuarioGenero             NVARCHAR(10)  NULL,
        PantallaGeneracion        NVARCHAR(10)  NULL,
        FechaGeneracion           DATE          NULL,
        HoraGeneracion            TIME(0)       NULL,
        NumeroCamion              NVARCHAR(6)   NULL,
        CapacidadCamionKgs        DECIMAL(15,3) NULL,
        PropietarioCamion         NVARCHAR(30)  NULL,
        NumeroMotorista           DECIMAL(5,0)  NULL,
        NombreMotorista           NVARCHAR(30)  NULL,
        NumeroEmpleado1           DECIMAL(5,0)  NULL,
        NombreEmpleado1           NVARCHAR(30)  NULL,
        NumeroEmpleado2           DECIMAL(5,0)  NULL,
        NombreEmpleado2           NVARCHAR(30)  NULL,
        NumeroEmpleado3           DECIMAL(5,0)  NULL,
        NombreEmpleado3           NVARCHAR(30)  NULL,
        NumeroEmpleado4           DECIMAL(5,0)  NULL,
        NombreEmpleado4           NVARCHAR(30)  NULL,
        CodigoRuta                NVARCHAR(6)   NULL,
        DescripcionRuta           NVARCHAR(30)  NULL,
        FechaUltimaModificacion   DATE          NULL,
        HoraUltimaModificacion    TIME(0)       NULL,
        EstatusEnvio              NVARCHAR(1)   NULL,
        PesoTotalEnvio            DECIMAL(9,3)  NULL,
        NumeroPlaca               NVARCHAR(10)  NULL,
        Dato1                     NVARCHAR(30)  NULL,
        Dato2                     NVARCHAR(30)  NULL,
        EsVigente                 BIT           NOT NULL CONSTRAINT DF_dw_factEnvios_EsVigente DEFAULT (1),
        HashDiff                  BINARY(32)    NOT NULL,
        FechaCargaDw              DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_factEnvios_FechaCargaDw DEFAULT (SYSDATETIME()),
        RunId                     INT           NULL,
        CONSTRAINT UQ_dw_factEnvios_NumeroEnvio UNIQUE (NumeroEnvio)
    );
END
GO
