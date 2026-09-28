"""
Silver: stg.factGuiasRemision -> [int].factGuiasRemision (tipado, fechas y
horas AAAAMMDD/HHMMSS a DATE/TIME).

Todo ocurre dentro de JAREMAR -- el trabajo real lo hace
[int].usp_MergeFactGuiasRemision; este script solo orquesta el ciclo de
control (registro de proceso, log de corrida, watermark).

Como UNDIS100 no tiene llave unica, el SP no hace MERGE: REEMPLAZA en [int]
el rango de fechas de registro que trae stg (borra D100F1 >= MIN(stg) e
inserta stg completo). Asi recoge anulaciones y borrados dentro de la
ventana del extract sin inventar una llave.

Este es el UNICO paso que mueve el watermark "GuiasRemision" (el extract solo
lo lee), con MAX(D100F1) real de [int] tras un reemplazo exitoso.

Uso:
    python db/etl/factGuiasRemision/load_silver_fact_guias_remision.py [--env-file .env]
"""
import argparse
import datetime
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
PROCESO = "GuiasRemision_Silver"


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
        PROCESO, "GuiasRemision", "stg", "stg", "factGuiasRemision", "int", "factGuiasRemision", "Incremental",
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

    Silver reemplaza en [int] el rango que trae stg: con un stg incompleto (extract
    caido a medias) o viejo, borraria filas buenas o re-aplicaria una ventana vieja.
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
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
        verificar_extracts_completos(cur, ["GuiasRemision"])
        cur.execute("EXEC [int].usp_MergeFactGuiasRemision @RunId = ?", run_id)
        filas_leidas, filas_insertadas, filas_actualizadas, filas_ignoradas, filas_eliminadas, desde = cur.fetchone()
        print(
            f"Reemplazo desde {desde}: Leidas: {filas_leidas} / Eliminadas: {filas_eliminadas} / "
            f"Insertadas: {filas_insertadas} / Ignoradas (sin fecha de registro): {filas_ignoradas}"
        )

        finalizar_run(
            cur, run_id, "EXITO",
            filas_leidas=filas_leidas, filas_insertadas=filas_insertadas,
            filas_actualizadas=filas_actualizadas, filas_ignoradas=filas_ignoradas,
        )

        cur.execute("SELECT MAX(D100F1) FROM [int].factGuiasRemision")
        nuevo_max = cur.fetchone()[0]
        if nuevo_max is not None:
            nueva_fecha_hora = datetime.datetime.combine(nuevo_max, datetime.time())
            cur.execute(
                "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
                "GuiasRemision", nueva_fecha_hora, "Incremental",
            )
            print(f"Watermark 'GuiasRemision' actualizado a {nueva_fecha_hora}")
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
