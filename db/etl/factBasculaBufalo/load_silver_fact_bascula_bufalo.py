"""
Silver: stg.factBasculaBufalo -> [int].factBasculaBufalo (tipado, fechas AAAAMMDD a DATE, horas
HHMM/HHMMSS a TIME, MERGE incremental por la llave construida).

Todo ocurre dentro de JAREMAR -- el trabajo real lo hace [int].usp_MergeFactBasculaBufalo
(migracion 204); este script solo orquesta el ciclo de control (registro de proceso, log de
corrida, watermark).

Nunca borra: inserta lo nuevo, actualiza lo que cambio (HashDiff) y deja con EsVigente = 0 lo
que falte en el AS400, pero solo dentro de la ventana que el extract trajo completa (la lee del
watermark "BasculaBufalo" que deja el extract; 1900-01-01 = extract completo). Si la corrida
daria de baja mas de --max-bajas boletas, aborta sin tocar nada.

Este es el UNICO paso que mueve el watermark "BasculaBufalo_Silver" (el extract solo lo lee):
MAX(FECHAGEN) de [int] sin pasar de hoy.

Uso:
    python db/etl/factBasculaBufalo/load_silver_fact_bascula_bufalo.py [--env-file .env] [--max-bajas N]
"""
import argparse
import datetime
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
PROCESO = "BasculaBufalo_Silver"
EXTRACT = "BasculaBufalo"
MAX_BAJAS = 200


def load_env(path: Path) -> dict:
    env = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k] = v
    return env


def connect_jaremar(env: dict) -> pyodbc.Connection:
    conn_str = (
        f"DRIVER={{{env['JAREMAR_ODBC_DRIVER']}}};"
        f"SERVER={env['JAREMAR_SERVER']},{env['JAREMAR_PORT']};"
        f"DATABASE={env['JAREMAR_DATABASE']};"
    )
    if env.get("JAREMAR_AUTH_MODE", "sql").lower() == "windows":
        conn_str += "Trusted_Connection=yes;"
    else:
        conn_str += f"UID={env['JAREMAR_USER']};PWD={env['JAREMAR_PASSWORD']};"
    conn_str += "TrustServerCertificate=yes;"
    return pyodbc.connect(conn_str, timeout=15)


def registrar_proceso(cur: pyodbc.Cursor) -> int:
    cur.execute(
        """
        DECLARE @pid INT;
        EXEC dbo.usp_Etl_ProcesoRegistrar
            @Proceso = ?, @Dominio = ?, @SistemaOrigen = ?,
            @EsquemaOrigen = ?, @TablaOrigen = ?,
            @EsquemaDestino = ?, @TablaDestino = ?, @TipoCarga = ?,
            @ProcesoId = @pid OUTPUT;
        SELECT @pid;
        """,
        PROCESO, "Basculas", "stg", "stg", "factBasculaBufalo", "int", "factBasculaBufalo", "Incremental",
    )
    return cur.fetchone()[0]


def finalizar_run(cur, run_id, estado, **kwargs):
    cur.execute(
        """
        EXEC dbo.usp_Etl_RunFinalizar
            @RunId = ?, @Estado = ?,
            @FilasLeidas = ?, @FilasInsertadas = ?, @FilasActualizadas = ?, @FilasIgnoradas = ?,
            @MensajeError = ?, @TareaError = ?
        """,
        run_id, estado,
        kwargs.get("filas_leidas"), kwargs.get("filas_insertadas"),
        kwargs.get("filas_actualizadas"), kwargs.get("filas_ignoradas"),
        kwargs.get("mensaje_error"), kwargs.get("tarea_error"),
    )


def verificar_extracts_completos(cur: pyodbc.Cursor, extracts: list) -> None:
    """Aborta si el extract no termino bien o no se corrio desde el ultimo Silver exitoso.

    Silver da de baja lo que falte en la ventana de stg: con un stg incompleto (extract
    caido a medias) o viejo, marcaria como no vigentes boletas buenas.
    """
    cur.execute(
        """
        SELECT TOP 1 r.FechaInicio FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE p.ProcesoNombre = ? AND r.Estado = 'EXITO' ORDER BY r.RunId DESC
        """,
        PROCESO,
    )
    row = cur.fetchone()
    ultimo_silver = row[0] if row else None

    for extract in extracts:
        cur.execute(
            """
            SELECT TOP 1 r.Estado, r.FechaFin FROM dbo.EtlRunLog r
            JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
            WHERE p.ProcesoNombre = ? ORDER BY r.RunId DESC
            """,
            extract,
        )
        row = cur.fetchone()
        if row is None:
            raise RuntimeError(f"El extract {extract} nunca se ha corrido; no se puede ejecutar Silver.")
        estado, fecha_fin = row
        if estado not in ("EXITO", "ADVERTENCIA"):
            raise RuntimeError(f"La ultima corrida del extract {extract} termino en estado {estado}; corrigela antes de Silver.")
        if ultimo_silver is not None and fecha_fin is not None and fecha_fin <= ultimo_silver:
            raise RuntimeError(f"El extract {extract} no se ha vuelto a correr desde el ultimo Silver exitoso.")


def ventana_del_extract(cur: pyodbc.Cursor) -> "datetime.date | None":
    """Fecha desde la que el ultimo extract trajo todo; None = trajo la tabla completa."""
    cur.execute("EXEC dbo.usp_Etl_WatermarkObtener @Proceso = ?", EXTRACT)
    row = cur.fetchone()
    if row is None or row[1] is None:
        raise RuntimeError(f"El extract {EXTRACT} no dejo su ventana en el watermark.")
    return None if row[1].year <= 1900 else row[1].date()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--max-bajas", type=int, default=MAX_BAJAS,
                        help=f"Maximo de boletas que una corrida puede dar de baja (default {MAX_BAJAS}).")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    conn = connect_jaremar(env)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SET NOCOUNT ON")

    registrar_proceso(cur)
    conn.commit()

    cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", PROCESO)
    run_id = cur.fetchone()[0]
    conn.commit()
    print(f"RunId: {run_id}")

    try:
        verificar_extracts_completos(cur, [EXTRACT])
        ventana = ventana_del_extract(cur)
        print(f"Ventana del extract: {'tabla completa' if ventana is None else f'desde {ventana}'}")
        cur.execute(
            "EXEC [int].usp_MergeFactBasculaBufalo @RunId = ?, @VentanaDesde = ?, @MaxBajas = ?",
            run_id, ventana, args.max_bajas,
        )
        leidas, insertadas, actualizadas, ignoradas, bajas, repetidas, sin_fecha = cur.fetchone()
        print(
            f"Leidas: {leidas} / Insertadas: {insertadas} / Actualizadas: {actualizadas} / "
            f"Sin cambio: {ignoradas} / Dadas de baja: {bajas} / "
            f"Repetidas (misma llave): {repetidas} / Sin fecha valida: {sin_fecha}"
        )

        finalizar_run(
            cur, run_id, "EXITO",
            filas_leidas=leidas, filas_insertadas=insertadas,
            filas_actualizadas=actualizadas + bajas, filas_ignoradas=ignoradas,
        )

        cur.execute("SELECT MAX(FECHAGEN) FROM [int].factBasculaBufalo WHERE FECHAGEN <= CAST(GETDATE() AS DATE)")
        nuevo_max = cur.fetchone()[0]
        if nuevo_max is not None:
            nueva_fecha_hora = datetime.datetime.combine(nuevo_max, datetime.time())
            cur.execute(
                "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
                PROCESO, nueva_fecha_hora, "Incremental",
            )
            print(f"Watermark '{PROCESO}' actualizado a {nueva_fecha_hora}")
        conn.commit()
    except Exception as exc:
        conn.rollback()
        finalizar_run(cur, run_id, "ERROR", mensaje_error=str(exc), tarea_error="Merge Silver")
        conn.commit()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    print("Carga Silver completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
