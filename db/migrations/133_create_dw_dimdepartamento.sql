-- 133: dw.dimDepartamento -- dimension de referencia estatica (NO viene
-- del AS400, no hay tabla de departamentos geograficos en PROLX835F --
-- confirmado revisando GSV y CDP, ver comentario en migracion de dimPais).
-- Datos: 18 departamentos de Honduras + 22 de Guatemala + 14 de El
-- Salvador = 54 filas, con codigo ISO 3166-2 (fuente: Wikipedia
-- ISO_3166-2:HN/GT/SV, 2026-09-22).
-- Sin capa stg/int -- no hay sistema origen que aterrizar, se siembra
-- directo en dw via esta migracion (documentado explicitamente por que se
-- rompe el patron habitual de 3 capas del resto del proyecto).

IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'dw' AND t.name = 'dimDepartamento'
)
BEGIN
    CREATE TABLE dw.dimDepartamento (
        DepartamentoKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dw_dimDepartamento PRIMARY KEY,
        PaisKey              INT           NOT NULL CONSTRAINT FK_dw_dimDepartamento_dimPais REFERENCES dw.dimPais(PaisKey),
        CodigoIso3166_2       NVARCHAR(6)   NOT NULL,
        NombreDepartamento    NVARCHAR(50)  NOT NULL,
        FechaCargaDw          DATETIME2(7)  NOT NULL CONSTRAINT DF_dw_dimDepartamento_FechaCargaDw DEFAULT (SYSDATETIME()),
        CONSTRAINT UQ_dw_dimDepartamento_Codigo UNIQUE (CodigoIso3166_2)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dw.dimDepartamento)
BEGIN
    INSERT INTO dw.dimDepartamento (PaisKey, CodigoIso3166_2, NombreDepartamento)
    SELECT p.PaisKey, v.Codigo, v.Nombre
    FROM (VALUES
        ('HND', 'HN-AT', N'Atlantida'),
        ('HND', 'HN-CH', N'Choluteca'),
        ('HND', 'HN-CL', N'Colon'),
        ('HND', 'HN-CM', N'Comayagua'),
        ('HND', 'HN-CP', N'Copan'),
        ('HND', 'HN-CR', N'Cortes'),
        ('HND', 'HN-EP', N'El Paraiso'),
        ('HND', 'HN-FM', N'Francisco Morazan'),
        ('HND', 'HN-GD', N'Gracias a Dios'),
        ('HND', 'HN-IN', N'Intibuca'),
        ('HND', 'HN-IB', N'Islas de la Bahia'),
        ('HND', 'HN-LP', N'La Paz'),
        ('HND', 'HN-LE', N'Lempira'),
        ('HND', 'HN-OC', N'Ocotepeque'),
        ('HND', 'HN-OL', N'Olancho'),
        ('HND', 'HN-SB', N'Santa Barbara'),
        ('HND', 'HN-VA', N'Valle'),
        ('HND', 'HN-YO', N'Yoro'),
        ('GTM', 'GT-16', N'Alta Verapaz'),
        ('GTM', 'GT-15', N'Baja Verapaz'),
        ('GTM', 'GT-04', N'Chimaltenango'),
        ('GTM', 'GT-20', N'Chiquimula'),
        ('GTM', 'GT-02', N'El Progreso'),
        ('GTM', 'GT-05', N'Escuintla'),
        ('GTM', 'GT-01', N'Guatemala'),
        ('GTM', 'GT-13', N'Huehuetenango'),
        ('GTM', 'GT-18', N'Izabal'),
        ('GTM', 'GT-21', N'Jalapa'),
        ('GTM', 'GT-22', N'Jutiapa'),
        ('GTM', 'GT-17', N'Peten'),
        ('GTM', 'GT-09', N'Quetzaltenango'),
        ('GTM', 'GT-14', N'Quiche'),
        ('GTM', 'GT-11', N'Retalhuleu'),
        ('GTM', 'GT-03', N'Sacatepequez'),
        ('GTM', 'GT-12', N'San Marcos'),
        ('GTM', 'GT-06', N'Santa Rosa'),
        ('GTM', 'GT-07', N'Solola'),
        ('GTM', 'GT-10', N'Suchitepequez'),
        ('GTM', 'GT-08', N'Totonicapan'),
        ('GTM', 'GT-19', N'Zacapa'),
        ('SLV', 'SV-AH', N'Ahuachapan'),
        ('SLV', 'SV-CA', N'Cabanas'),
        ('SLV', 'SV-CH', N'Chalatenango'),
        ('SLV', 'SV-CU', N'Cuscatlan'),
        ('SLV', 'SV-LI', N'La Libertad'),
        ('SLV', 'SV-PA', N'La Paz'),
        ('SLV', 'SV-UN', N'La Union'),
        ('SLV', 'SV-MO', N'Morazan'),
        ('SLV', 'SV-SM', N'San Miguel'),
        ('SLV', 'SV-SS', N'San Salvador'),
        ('SLV', 'SV-SV', N'San Vicente'),
        ('SLV', 'SV-SA', N'Santa Ana'),
        ('SLV', 'SV-SO', N'Sonsonate'),
        ('SLV', 'SV-US', N'Usulutan')
    ) v(PaisAlpha3, Codigo, Nombre)
    JOIN dw.dimPais p ON p.CodigoPaisAlpha3 = v.PaisAlpha3;
END
GO
