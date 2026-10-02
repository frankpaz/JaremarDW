"""
Silver: stg.factEnvios -> [int].factEnvios (tipado, dedup por ENCENV, MERGE por huella).

Todo ocurre dentro de JAREMAR -- el trabajo real lo hace
[int].usp_MergeFactEnvios (migracion 247); este script solo orquesta el ciclo de control
(registro de proceso, log de corrida, watermark).

stg solo trae los dias que no cuadraron con el AS400 (stg.factEnvios_Periodos). Silver
inserta y actualiza lo que viene, y da de baja (EsVigente = 0, nunca borra) los envios de
esos dias que ya no estan en el AS400. Antes verifica que el extract termino bien y se corrio
despues del ultimo silver exitoso: con un stg incompleto o viejo daria de baja envios buenos.
Si la corrida daria de baja mas de --max-bajas envios, aborta sin tocar nada.

Uso:
    python db/etl/factEnvios/load_silver_fact_envios.py [--env-file .env] [--max-bajas N]
"""
import argparse
import datetime
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
PROCESO = "Envios_Silver"
EXTRACT = "Envios"
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
        PROCESO, "Envios", "stg", "stg", "factEnvios", "int", "factEnvios", "Incremental",
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


def verificar_extract(cur: pyodbc.Cursor) -> None:
    """Aborta si el extract no termino bien o no se corrio desde el ultimo silver exitoso."""
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

    cur.execute(
        """
        SELECT TOP 1 r.Estado, r.FechaFin FROM dbo.EtlRunLog r
        JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
        WHERE p.ProcesoNombre = ? ORDER BY r.RunId DESC
        """,
        EXTRACT,
    )
    row = cur.fetchone()
    if row is None:
        raise RuntimeError(f"El extract {EXTRACT} nunca se ha corrido; no se puede ejecutar Silver.")
    estado, fecha_fin = row
    if estado not in ("EXITO", "ADVERTENCIA"):
        raise RuntimeError(f"La ultima corrida del extract {EXTRACT} termino en estado {estado}; corrigela antes de Silver.")
    if ultimo_silver is not None and fecha_fin is not None and fecha_fin <= ultimo_silver:
        raise RuntimeError(f"El extract {EXTRACT} no se ha vuelto a correr desde el ultimo Silver exitoso.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--max-bajas", type=int, default=MAX_BAJAS,
                        help=f"Maximo de envios que una corrida puede dar de baja (default {MAX_BAJAS}).")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    conn = connect_jaremar(env)
    conn.autocommit = False
    cur = conn.cursor()

    registrar_proceso(cur)
    conn.commit()

    cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", PROCESO)
    run_id = cur.fetchone()[0]
    conn.commit()
    print(f"RunId: {run_id}")

    try:
        verificar_extract(cur)
        cur.execute("EXEC [int].usp_MergeFactEnvios @RunId = ?, @MaxBajas = ?", run_id, args.max_bajas)
        filas_leidas, filas_insertadas, filas_actualizadas, filas_ignoradas, filas_bajas = cur.fetchone()
        print(
            f"Leidas: {filas_leidas} / Insertadas: {filas_insertadas} / "
            f"Actualizadas: {filas_actualizadas} / Sin cambio: {filas_ignoradas} / Dadas de baja: {filas_bajas}"
        )

        finalizar_run(
            cur, run_id, "EXITO",
            filas_leidas=filas_leidas, filas_insertadas=filas_insertadas,
            filas_actualizadas=filas_actualizadas, filas_ignoradas=filas_ignoradas,
        )
        cur.execute(
            "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
            PROCESO, datetime.datetime.now(), "Incremental",
        )
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
