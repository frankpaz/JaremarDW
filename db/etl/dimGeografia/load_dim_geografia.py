"""
Carga de las dimensiones geograficas de referencia: dw.dimDepartamento y
dw.dimMunicipio (no vienen del AS400, ver migracion 141).

Ejecuta dw.usp_MergeDimDepartamento y luego dw.usp_MergeDimMunicipio, cada
uno como su propio proceso del framework de control. Requiere que
dw.dimPais ya este cargada (corre dimPais antes); si falta la dimension
padre, el SP falla con un mensaje claro y este script se detiene.

Uso:
    python db/etl/dimGeografia/load_dim_geografia.py [--env-file .env]
"""
import argparse
import datetime
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "db"))
from migrate import build_connection, load_env  # noqa: E402

PASOS = [
    # (proceso, SP, tabla destino)
    ("DimDepartamento_Gold", "dw.usp_MergeDimDepartamento", "dimDepartamento"),
    ("DimMunicipio_Gold", "dw.usp_MergeDimMunicipio", "dimMunicipio"),
]


def ejecutar_paso(conn, proceso: str, sp: str, tabla: str) -> None:
    cur = conn.cursor()
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
        proceso, "Geografia", "Referencia", "dw", tabla, "dw", tabla, "FULL",
    )
    cur.fetchone()
    conn.commit()

    cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", proceso)
    run_id = cur.fetchone()[0]
    conn.commit()
    print(f"[{proceso}] RunId: {run_id}")

    try:
        cur.execute(f"EXEC {sp} @RunId = ?", run_id)
        leidas, insertadas, actualizadas, ignoradas = cur.fetchone()
        print(f"[{proceso}] Leidas: {leidas} / Insertadas: {insertadas} / Actualizadas: {actualizadas} / Sin cambio: {ignoradas}")
        cur.execute(
            """
            EXEC dbo.usp_Etl_RunFinalizar
                @RunId = ?, @Estado = ?,
                @FilasLeidas = ?, @FilasInsertadas = ?, @FilasActualizadas = ?, @FilasIgnoradas = ?,
                @MensajeError = ?, @TareaError = ?
            """,
            run_id, "EXITO", leidas, insertadas, actualizadas, ignoradas, None, None,
        )
        cur.execute(
            "EXEC dbo.usp_Etl_WatermarkActualizar @Proceso = ?, @NuevaFechaHora = ?, @TipoCarga = ?",
            proceso, datetime.datetime.now(), "FULL",
        )
        conn.commit()
    except Exception as exc:
        conn.rollback()
        cur.execute(
            """
            EXEC dbo.usp_Etl_RunFinalizar
                @RunId = ?, @Estado = ?,
                @FilasLeidas = ?, @FilasInsertadas = ?, @FilasActualizadas = ?, @FilasIgnoradas = ?,
                @MensajeError = ?, @TareaError = ?
            """,
            run_id, "ERROR", None, None, None, None, str(exc), "Merge Gold",
        )
        conn.commit()
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    conn = build_connection(load_env(Path(args.env_file)))
    conn.autocommit = False
    try:
        for proceso, sp, tabla in PASOS:
            ejecutar_paso(conn, proceso, sp, tabla)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    print("Carga de dimensiones geograficas completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
