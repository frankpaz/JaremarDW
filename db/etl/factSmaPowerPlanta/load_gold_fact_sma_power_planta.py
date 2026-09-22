"""
Gold: [int].factSmaPowerPlanta -> dw.factSmaPowerPlanta (INCREMENTAL).

Requiere que dw.dimSmaPlants y dw.dimSmaDevices ya esten cargados
(dw.usp_MergeFactSmaPowerPlanta resuelve SmaPlantaKey/SmaDeviceKey contra
esas tablas via LEFT JOIN). El merge solo procesa filas cuyo FechaCargaInt
en [int] sea posterior al ultimo watermark de este proceso (independiente
del watermark de Silver). Todo ocurre dentro de JAREMAR -- este script solo
orquesta el ciclo de control (registro de proceso, log de corrida,
watermark).

Uso:
    python db/etl/factSmaPowerPlanta/load_gold_fact_sma_power_planta.py [--env-file .env]
"""
import argparse
import sys
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent.parent.parent
PROCESO = "SmaPowerPlanta_Gold"


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
        PROCESO, "Solar", "int", "int", "factSmaPowerPlanta", "dw", "factSmaPowerPlanta", "Incremental",
    )
    return cur.fetchone()[0]


def obtener_watermark(cur: pyodbc.Cursor):
    cur.execute("EXEC dbo.usp_Etl_WatermarkObtener @Proceso = ?", PROCESO)
    row = cur.fetchone()
    return row.UltimaCargaFechaHora if row else None


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    conn = connect_jaremar(env)
    conn.autocommit = False
    cur = conn.cursor()

    registrar_proceso(cur)
    conn.commit()

    ultimo_watermark = obtener_watermark(cur)
    conn.commit()

    cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", PROCESO)
    run_id = cur.fetchone()[0]
    conn.commit()
    print(f"RunId: {run_id} / Watermark previo: {ultimo_watermark}")

    try:
        cur.execute(
            "EXEC dw.usp_MergeFactSmaPowerPlanta @RunId = ?, @UltimoWatermark = ?",
            run_id, ultimo_watermark,
        )
        filas_leidas, filas_insertadas, filas_actualizadas, filas_ignoradas, nuevo_watermark = cur.fetchone()
        print(
            f"Leidas: {filas_leidas} / Insertadas: {filas_insertadas} / "
            f"Actualizadas: {filas_actualizadas} / Sin cambio: {filas_ignoradas} / "
            f"Nuevo watermark: {nuevo_watermark}"
        )

        finalizar_run(
            cur, run_id, "EXITO",
            filas_leidas=filas_leidas, filas_insertadas=filas_insertadas,
            filas_actualizadas=filas_actualizadas, filas_ignoradas=filas_ignoradas,
        )
        cur.execute(
            "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
            PROCESO, nuevo_watermark, "Incremental",
        )
        conn.commit()
    except Exception as exc:
        conn.rollback()
        finalizar_run(cur, run_id, "ERROR", mensaje_error=str(exc), tarea_error="Merge Gold")
        conn.commit()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    print("Carga Gold completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
