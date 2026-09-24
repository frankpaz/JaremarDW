"""
Carga masiva del plan de generacion de energia desde el Excel del equipo de
planta ('Solar Jaremar - Reporte Ejecutivo.xlsx') hacia stg -> [int] -> dw.

Lee UNA hoja, 'Plan_Diario_INV': Periodo | <ID inversor 1> | <ID inversor 2> ...
(kWh planeados por dia de cada inversor). Cada celda pasa a una fila
(Fecha, CodigoInversor, PlanKwh). Los resumenes por PI y por plantel NO se
cargan: se calculan en el DW (dw.vwPlanDiarioPI / vwPlanDiarioPlantel) a partir
del plan por inversor y de las dimensiones de dispositivos (dimSmaDevices,
dimSmaPlants).

Valida antes de escribir (cabecera 'Periodo', fechas validas y sin duplicados,
valores numericos >= 0). Una celda vacia se interpreta como 'sin plan' para ese
dia e inversor y se omite (un 0 es una afirmacion distinta y se carga con aviso).
Si hay errores no se escribe nada. Si el archivo trae la hoja 'Inversores' (ID_Inversor, SN),
lee el serial de cada inversor como respaldo para enlazarlo con dimSmaDevices (algunos
dispositivos SMA no traen el ID en su nombre). Tambien avisa (sin bloquear) de los IDs de
inversor que no resuelven contra dw.dimSmaDevices ni dw.dimDeviceCapacity: se
cargan con las llaves de dispositivo en NULL y se rellenan cuando la dimension
los incluya.

Cada carga entra con una --version y queda en el historial: para cada fecha e
inversor queda vigente la version cargada mas recientemente; las fechas que la
nueva carga no trae conservan su version anterior. Recargar la misma version es
idempotente.

Requiere openpyxl (solo para este cargador).

Uso:
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --version V1 --dry-run
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --version V1 [--fuente "..."] [--anio 2026] [--env-file .env.prod]
"""
import argparse
import datetime
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "db"))
from migrate import build_connection, load_env  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOJA_PLAN = "Plan_Diario_INV"
HOJA_INVERSORES = "Inversores"
FUENTE_DEFECTO = "Solar Jaremar - Reporte Ejecutivo"


# --- Lectura y validacion del Excel ------------------------------------------

def leer_plan(wb, errores: list, avisos: list) -> list:
    if HOJA_PLAN not in wb.sheetnames:
        errores.append(f"No existe la hoja '{HOJA_PLAN}'. Hojas: {wb.sheetnames}")
        return []
    filas = list(wb[HOJA_PLAN].iter_rows(values_only=True))
    idx = next((i for i, r in enumerate(filas) if r and str(r[0] or "").strip().upper() == "PERIODO"), None)
    if idx is None:
        errores.append(f"En '{HOJA_PLAN}' no se encontro la cabecera 'Periodo' en la primera columna.")
        return []
    inversores = [(j, str(c).strip()) for j, c in enumerate(filas[idx]) if j > 0 and c is not None and str(c).strip()]
    if not inversores:
        errores.append(f"'{HOJA_PLAN}' no tiene columnas de inversor despues de 'Periodo'.")
        return []
    ids = [i for _, i in inversores]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        errores.append(f"'{HOJA_PLAN}': el inversor '{dup}' aparece en mas de una columna.")

    resultado, fechas_vistas, vacias, ceros = [], set(), {}, {}
    for n_fila, r in enumerate(filas[idx + 1:], start=idx + 2):
        if r is None or r[0] is None:
            continue
        if not isinstance(r[0], (datetime.datetime, datetime.date)):
            errores.append(f"'{HOJA_PLAN}' fila {n_fila}: el Periodo no es una fecha: {r[0]!r}")
            continue
        fecha = r[0].date() if isinstance(r[0], datetime.datetime) else r[0]
        if fecha in fechas_vistas:
            errores.append(f"'{HOJA_PLAN}' fila {n_fila}: fecha duplicada {fecha}.")
            continue
        fechas_vistas.add(fecha)
        for j, inv in inversores:
            v = r[j] if j < len(r) else None
            if v is None:
                vacias[inv] = vacias.get(inv, 0) + 1
            elif isinstance(v, bool) or not isinstance(v, (int, float)):
                errores.append(f"'{HOJA_PLAN}' fila {n_fila}, {inv}: valor no numerico {v!r}.")
            elif v < 0:
                errores.append(f"'{HOJA_PLAN}' fila {n_fila}, {inv}: valor negativo {v}.")
            else:
                if v == 0:
                    ceros[inv] = ceros.get(inv, 0) + 1
                resultado.append({"Fecha": fecha, "CodigoInversor": inv, "PlanKwh": round(float(v), 8)})
    if not fechas_vistas:
        errores.append(f"'{HOJA_PLAN}' no tiene filas con fecha.")
    for inv, n in sorted(vacias.items()):
        avisos.append(f"{inv}: {n} dia(s) sin valor (celda vacia); se omiten, no se cargan como 0.")
    for inv, n in sorted(ceros.items()):
        avisos.append(f"{inv}: {n} dia(s) con plan 0 kWh (se interpreta como 'se planifica no generar').")
    fechas = sorted(fechas_vistas)
    if fechas:
        faltan = (fechas[-1] - fechas[0]).days + 1 - len(fechas)
        if faltan > 0:
            avisos.append(f"Hay {faltan} fecha(s) faltantes dentro del rango {fechas[0]} a {fechas[-1]}.")
    return resultado


def leer_seriales(wb, avisos: list) -> dict:
    """ID de inversor -> serial, de la hoja Inversores (opcional)."""
    if HOJA_INVERSORES not in wb.sheetnames:
        avisos.append(f"No hay hoja '{HOJA_INVERSORES}': los inversores se enlazaran solo por nombre del dispositivo.")
        return {}
    filas = list(wb[HOJA_INVERSORES].iter_rows(values_only=True))
    idx = next((i for i, r in enumerate(filas) if r and str(r[0] or "").strip().upper() == "ID_INVERSOR"), None)
    if idx is None:
        avisos.append(f"En '{HOJA_INVERSORES}' no se encontro la cabecera 'ID_Inversor'; se ignora.")
        return {}
    cab = {str(c).strip().upper(): j for j, c in enumerate(filas[idx]) if c is not None}
    if "SN" not in cab:
        avisos.append(f"'{HOJA_INVERSORES}' no tiene columna 'SN'; se ignora.")
        return {}
    return {str(r[0]).strip(): str(r[cab["SN"]]).strip() for r in filas[idx + 1:]
            if r and r[0] is not None and r[cab["SN"]] is not None}


def avisar_ids_sin_dimension(cur, plan: list, avisos: list) -> None:
    """IDs que no resuelven en dimSmaDevices (por nombre o por serial unico) ni en dimDeviceCapacity."""
    try:
        cur.execute("SELECT LEFT(DeviceName, CHARINDEX(' (SN', DeviceName + ' (SN') - 1) FROM dw.dimSmaDevices WHERE DeviceName IS NOT NULL")
        conocidos = {r[0].strip().upper() for r in cur.fetchall()}
        cur.execute("SELECT InverterId FROM dw.dimDeviceCapacity")
        conocidos |= {r[0].strip().upper() for r in cur.fetchall()}
        cur.execute("SELECT Serial FROM dw.dimSmaDevices WHERE Serial IS NOT NULL GROUP BY Serial HAVING COUNT(*) = 1")
        seriales_unicos = {str(r[0]).strip() for r in cur.fetchall()}
    except Exception:
        avisos.append("No se pudieron leer las dimensiones de dispositivos; se omite la revision de IDs.")
        return
    sin = sorted({p["CodigoInversor"] for p in plan
                  if p["CodigoInversor"].upper() not in conocidos and p.get("SerialInversor") not in seriales_unicos})
    if sin:
        avisos.append(f"{len(sin)} inversor(es) sin match en dimSmaDevices ni dimDeviceCapacity: {sin}. "
                      "Se cargan con las llaves de dispositivo en NULL y no entran en los resumenes por PI/plantel hasta que existan en la dimension.")


# --- Carga (framework de control ETL) -----------------------------------------

def ejecutar_paso(conn, proceso, origen, destino, fn):
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
        proceso, "PlanGeneracion", origen[0], origen[0], origen[1], destino[0], destino[1], "FULL",
    )
    cur.fetchone()
    conn.commit()
    cur.execute("EXEC dbo.usp_Etl_RunIniciar @Proceso = ?", proceso)
    run_id = cur.fetchone()[0]
    conn.commit()
    try:
        leidas, insertadas, actualizadas, ignoradas = fn(cur, run_id)
        print(f"  [{proceso}] leidas {leidas} / insertadas {insertadas} / actualizadas {actualizadas} / sin cambio {ignoradas}")
        cur.execute(
            "EXEC dbo.usp_Etl_RunFinalizar @RunId = ?, @Estado = ?, @FilasLeidas = ?, @FilasInsertadas = ?, "
            "@FilasActualizadas = ?, @FilasIgnoradas = ?, @MensajeError = ?, @TareaError = ?",
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
            "EXEC dbo.usp_Etl_RunFinalizar @RunId = ?, @Estado = ?, @FilasLeidas = ?, @FilasInsertadas = ?, "
            "@FilasActualizadas = ?, @FilasIgnoradas = ?, @MensajeError = ?, @TareaError = ?",
            run_id, "ERROR", None, None, None, None, str(exc), proceso,
        )
        conn.commit()
        raise


def cargar_stg(plan, archivo, fuente, version):
    def fn(cur, run_id):
        cur.execute("TRUNCATE TABLE stg.dimPlanGeneracion")
        cur.fast_executemany = True
        cur.executemany(
            "INSERT INTO stg.dimPlanGeneracion (Fecha, CodigoInversor, SerialInversor, PlanKwh, PlanFuente, PlanVersion, ArchivoOrigen, RunId) VALUES (?,?,?,?,?,?,?,?)",
            [(p["Fecha"], p["CodigoInversor"], p["SerialInversor"], p["PlanKwh"], fuente, version, archivo, run_id) for p in plan],
        )
        return len(plan), len(plan), 0, 0
    return fn


def ejecutar_sp(sp):
    def fn(cur, run_id):
        cur.execute(f"EXEC {sp} @RunId = ?", run_id)
        return tuple(cur.fetchone())
    return fn


def main() -> int:
    parser = argparse.ArgumentParser(description="Carga masiva del plan de generacion de energia (Plan_Diario_INV) desde Excel.")
    parser.add_argument("--archivo", required=True, help="Ruta del Excel (hoja Plan_Diario_INV).")
    parser.add_argument("--version", required=True, help="Identificador de la version del plan (ej. V1, 2026-08-16).")
    parser.add_argument("--fuente", default=FUENTE_DEFECTO, help=f"Origen del plan (default: '{FUENTE_DEFECTO}').")
    parser.add_argument("--anio", type=int, default=None, help="Si se indica, exige que todas las fechas sean de ese anio.")
    parser.add_argument("--dry-run", action="store_true", help="Solo valida y muestra el resumen; no escribe en la base.")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    ruta = Path(args.archivo)
    if not ruta.is_file():
        print(f"ERROR: no existe el archivo {ruta}", file=sys.stderr)
        return 2

    wb = openpyxl.load_workbook(ruta, data_only=True)
    errores, avisos = [], []
    plan = leer_plan(wb, errores, avisos)
    seriales = leer_seriales(wb, avisos) if plan else {}
    for p in plan:
        p["SerialInversor"] = seriales.get(p["CodigoInversor"])
    if args.anio and plan:
        fuera = sorted({p["Fecha"].year for p in plan if p["Fecha"].year != args.anio})
        if fuera:
            errores.append(f"Se esperaba el anio {args.anio} pero hay fechas de {fuera}.")

    print(f"Archivo: {ruta.name} | version: {args.version} | fuente: {args.fuente}")
    if plan:
        fechas = sorted({p["Fecha"] for p in plan})
        inversores = sorted({p["CodigoInversor"] for p in plan})
        print(f"Fechas: {fechas[0]} a {fechas[-1]} ({len(fechas)} dias) | inversores: {len(inversores)} | filas: {len(plan)}")
        print(f"Plan total: {sum(p['PlanKwh'] for p in plan):,.0f} kWh")

    conn = None
    if not errores and plan:
        conn = build_connection(load_env(Path(args.env_file)))
        conn.autocommit = False
        avisar_ids_sin_dimension(conn.cursor(), plan, avisos)

    for a in avisos:
        print(f"AVISO: {a}")
    if errores:
        for e in errores:
            print(f"ERROR: {e}", file=sys.stderr)
        print("No se escribio nada en la base.", file=sys.stderr)
        return 2
    if not plan:
        print("ERROR: el archivo no tiene filas de plan.", file=sys.stderr)
        return 2
    if args.dry_run:
        conn.close()
        print("Dry-run: validacion correcta, no se escribio nada.")
        return 0

    try:
        print("Cargando:")
        nombre = ruta.name
        pasos = [
            ("PlanGeneracion_Bronze", ("Excel", HOJA_PLAN), ("stg", "dimPlanGeneracion"), cargar_stg(plan, nombre, args.fuente, args.version)),
            ("PlanGeneracion_Silver", ("stg", "dimPlanGeneracion"), ("int", "dimPlanGeneracion"), ejecutar_sp("[int].usp_MergeDimPlanGeneracion")),
            ("PlanGeneracion_Gold", ("int", "dimPlanGeneracion"), ("dw", "dimPlanGeneracion"), ejecutar_sp("dw.usp_MergeDimPlanGeneracion")),
        ]
        for proceso, origen, destino, fn in pasos:
            ejecutar_paso(conn, proceso, origen, destino, fn)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    print("Carga del plan de generacion completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
