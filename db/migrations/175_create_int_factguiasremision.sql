-- 175: [int].factGuiasRemision -- version Silver de stg.factGuiasRemision (PROLXUSRF.UNDIS100).
-- Una fila por guia x factura x producto. SIN llave unica: el origen no tiene PK,
-- indices ni numero de linea (guia+factura+producto se repite en ~5 % de las filas y
-- hay duplicados exactos; discovery 2026-09-28). Por eso no hay PK ni HashDiff: la
-- carga reemplaza rangos de D100F1 (fecha de registro), y el indice clustered va
-- sobre esa columna. Historico desde 2025-01-01.
-- Fechas AAAAMMDD y horas HHMMSS numericas convertidas a DATE/TIME (0 o invalidas
-- -> NULL; D100FV trae fechas invalidas y futuras en el origen). Codigos numericos
-- a INT; cantidades, peso y valor sin cambios.

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'int' AND t.name = 'factGuiasRemision'
)
BEGIN
    CREATE TABLE [int].factGuiasRemision (
        D100CI          INT            NOT NULL,
        D100OR          INT            NULL,
        D100PF          NVARCHAR(2)    NULL,
        D100GC          INT            NULL,
        D100GS          INT            NULL,
        D100GD          INT            NULL,
        D100NG          INT            NOT NULL,
        D100NC          NVARCHAR(40)   NULL,
        D100NI          INT            NULL,
        D100NF          INT            NULL,
        D100FI          DATE           NULL,
        D100FF          DATE           NULL,
        D100EN          INT            NULL,
        D100MT          INT            NULL,
        D100FV          DATE           NULL,
        D100HR          TIME(0)        NULL,
        D100CM          NVARCHAR(6)    NULL,
        D100RM          NVARCHAR(6)    NULL,
        D100MF          INT            NULL,
        D100CL          INT            NULL,
        D100RC          NVARCHAR(16)   NULL,
        D100PE          INT            NULL,
        D100FC          INT            NULL,
        D100FE          DATE           NULL,
        D100PR          NVARCHAR(35)   NULL,
        D100CA          DECIMAL(15,3)  NULL,
        D100PK          DECIMAL(15,2)  NULL,
        D100VA          DECIMAL(15,2)  NULL,
        D100WS          NVARCHAR(10)   NULL,
        D100US          NVARCHAR(10)   NULL,
        D100F1          DATE           NOT NULL,
        D100H1          TIME(0)        NULL,
        D100ET          NVARCHAR(6)    NULL,
        FechaCargaInt   DATETIME2(7)   NOT NULL CONSTRAINT DF_Int_factGuiasRemision_FechaCargaInt DEFAULT (SYSDATETIME()),
        RunId           INT            NULL
    );
    CREATE CLUSTERED INDEX CIX_Int_factGuiasRemision_D100F1 ON [int].factGuiasRemision (D100F1);
    CREATE INDEX IX_Int_factGuiasRemision_FechaCargaInt ON [int].factGuiasRemision (FechaCargaInt) INCLUDE (D100F1);
END
GO
