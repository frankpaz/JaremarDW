"""
Carga masiva del plan de generacion de energia desde el Excel del equipo de
planta ('Solar Jaremar - Reporte Ejecutivo.xlsx') hacia stg -> [int] -> dw.

Lee dos hojas:
  Plan_Anual  MES | <plantel 1> | <plantel 2> ...   kWh del mes por plantel
              (12 filas, la fecha es el dia 1 de cada mes). Cada columna de
              plantel se desagrega a 12 filas (Anio, Mes, Plantel, PlanKwh).
  PI          ID_PI | Ubicacion | Capacidad_DC_kWp | Capacidad_AC_kW
              Catalogo de puntos de interconexion; base del reparto del plan
              de cada plantel entre sus PI (ver dw.vwPlanDiarioPI).

Valida antes de escribir nada (12 meses completos por plantel, valores
numericos y positivos, cabeceras esperadas, PI conocidos, un solo anio). Un
plantel con TODA su columna vacia se omite (sin plan, no es lo mismo que plan
en cero); una columna a medias es un error. Si algo falla, no se escribe nada.
Ademas muestra el PR implicito del plan contra las horas sol de dimGhiPlanDaily
como ADVERTENCIA (no bloquea).

Cada carga entra con una --version y queda en el historial: cargar una version
nueva del plan de un anio deja la anterior como historica (EsVigente = 0).
Recargar la misma version es idempotente.

Requiere openpyxl (solo para este cargador).

Uso:
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --version V1 --dry-run
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --version V1 [--fuente "..."] [--anio 2026] [--env-file .env.prod]
"""
import argparse
import datetime
import sys
import unicodedata
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(ROOT / "db"))
from migrate import build_connection, load_env  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOJA_PLAN = "Plan_Anual"
HOJA_PI = "PI"
FUENTE_DEFECTO = "Solar Jaremar - Reporte Ejecutivo"

# Mapeo PI (nombre normalizado: sin acentos, mayusculas) -> sitio del DW
# (dimGhiPlanDaily / factMeteoDaily). Un PI nuevo del Excel debe agregarse aqui.
SITIO_POR_PI = {
    "HARINAS": "harina",
    "DETERGENTE": "detergentes",
    "MARGARINA": "margarina",
    "JABON": "jabon",
    "PERFECTOR": "perfector",
    "PROALSA": "proalsa",
    "REFINERIA": "refineria",
    "EDIF ADMIN": "edif-admin",
}

PR_MIN, PR_MAX = 0.70, 0.90


def normalizar(texto) -> str:
    s = unicodedata.normalize("NFD", str(texto or ""))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return " ".join(s.upper().split())


# --- Lectura y validacion del Excel ------------------------------------------

def leer_plan(wb, errores: list, avisos: list) -> list:
    if HOJA_PLAN not in wb.sheetnames:
        errores.append(f"No existe la hoja '{HOJA_PLAN}'. Hojas: {wb.sheetnames}")
        return []
    filas = list(wb[HOJA_PLAN].iter_rows(values_only=True))
    idx = next((i for i, r in enumerate(filas) if r and normalizar(r[0]) == "MES"), None)
    if idx is None:
        errores.append(f"En '{HOJA_PLAN}' no se encontro la cabecera 'MES' en la primera columna.")
        return []
    cab = filas[idx]
    plantels = [(j, str(c).strip()) for j, c in enumerate(cab) if j > 0 and c is not None and str(c).strip()]
    if not plantels:
        errores.append(f"'{HOJA_PLAN}' no tiene columnas de plantel despues de 'MES'.")
        return []

    datos = []
    for r in filas[idx + 1:]:
        if r is None or r[0] is None:
            continue
        if not isinstance(r[0], (datetime.datetime, datetime.date)):
            errores.append(f"'{HOJA_PLAN}': valor de MES no es una fecha: {r[0]!r}")
            continue
        datos.append(r)

    anios = {r[0].year for r in datos}
    if len(anios) != 1:
        errores.append(f"'{HOJA_PLAN}' debe tener un solo anio; se encontraron: {sorted(anios)}")
        return []
    anio = anios.pop()

    resultado = []
    for j, plantel in plantels:
        col = {}
        for r in datos:
            if r[0].day != 1:
                errores.append(f"'{HOJA_PLAN}': la fecha {r[0]:%Y-%m-%d} no es el dia 1 del mes.")
            col[r[0].month] = r[j] if j < len(r) else None
        valores = [col.get(m) for m in range(1, 13)]
        if all(v is None for v in valores):
            avisos.append(f"Plantel '{plantel}': columna sin plan (todos los meses vacios); se omite.")
            continue
        faltan = [m for m in range(1, 13) if col.get(m) is None]
        if faltan:
            errores.append(f"Plantel '{plantel}': faltan valores para los meses {faltan}.")
            continue
        for m in range(1, 13):
            v = col[m]
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                errores.append(f"Plantel '{plantel}', mes {m}: valor no numerico {v!r}.")
            elif v < 0:
                errores.append(f"Plantel '{plantel}', mes {m}: valor negativo {v}.")
            else:
                if v == 0:
                    avisos.append(f"Plantel '{plantel}', mes {m}: plan en 0 kWh (se interpreta como 'no se planifica generar').")
                resultado.append({"Anio": anio, "Mes": m, "Plantel": plantel, "PlanKwh": round(float(v), 8)})
    return resultado


def leer_pi(wb, errores: list, avisos: list) -> list:
    if HOJA_PI not in wb.sheetnames:
        errores.append(f"No existe la hoja '{HOJA_PI}'. Hojas: {wb.sheetnames}")
        return []
    filas = list(wb[HOJA_PI].iter_rows(values_only=True))
    idx = next((i for i, r in enumerate(filas) if r and normalizar(r[0]) == "ID_PI"), None)
    if idx is None:
        errores.append(f"En '{HOJA_PI}' no se encontro la cabecera 'ID_PI'.")
        return []
    cab = {normalizar(c): j for j, c in enumerate(filas[idx]) if c is not None}
    req = {"ID_PI": "ID_PI", "UBICACION": "Ubicacion", "CAPACIDAD_DC_KWP": "Capacidad_DC_kWp", "CAPACIDAD_AC_KW": "Capacidad_AC_kW"}
    faltan = [nombre for k, nombre in req.items() if k not in cab]
    if faltan:
        errores.append(f"'{HOJA_PI}': faltan las columnas {faltan}.")
        return []

    resultado, vistos = [], set()
    for r in filas[idx + 1:]:
        if r is None or r[cab["ID_PI"]] is None:
            continue
        pi = str(r[cab["ID_PI"]]).strip()
        dc, ac, plantel = r[cab["CAPACIDAD_DC_KWP"]], r[cab["CAPACIDAD_AC_KW"]], r[cab["UBICACION"]]
        clave = normalizar(pi)
        if clave in vistos:
            errores.append(f"'{HOJA_PI}': PI duplicado '{pi}'.")
            continue
        vistos.add(clave)
        if clave not in SITIO_POR_PI:
            errores.append(f"'{HOJA_PI}': el PI '{pi}' no esta en SITIO_POR_PI del cargador; agregalo con su sitio del DW.")
            continue
        if not plantel or not str(plantel).strip():
            errores.append(f"'{HOJA_PI}': el PI '{pi}' no tiene Ubicacion.")
            continue
        if not isinstance(dc, (int, float)) or dc <= 0 or not isinstance(ac, (int, float)) or ac <= 0:
            errores.append(f"'{HOJA_PI}': el PI '{pi}' necesita capacidades DC y AC numericas > 0 (DC={dc!r}, AC={ac!r}).")
            continue
        resultado.append({
            "CodigoPI": pi, "Plantel": str(plantel).strip(), "CodigoSitio": SITIO_POR_PI[clave],
            "CapacidadDcKwp": round(float(dc), 4), "CapacidadAcKw": round(float(ac), 4),
        })
    return resultado


def cruzar(plan: list, pis: list, errores: list, avisos: list) -> None:
    plantels_plan = {p["Plantel"] for p in plan}
    plantels_pi = {p["Plantel"] for p in pis}
    for pl in sorted(plantels_plan - plantels_pi):
        errores.append(f"El plantel '{pl}' tiene plan pero ningun PI en la hoja '{HOJA_PI}'; no se puede repartir.")
    for pl in sorted(plantels_pi - plantels_plan):
        avisos.append(f"La ubicacion '{pl}' de la hoja '{HOJA_PI}' no tiene plan en este archivo.")


def advertencia_pr(cur, plan: list, pis: list) -> list:
    """PR implicito = plan del mes / SUM(kWp DC del PI x horas sol plan del mes de su sitio)."""
    try:
        cur.execute("SELECT Site, MonthOfYear, SUM(HsfP50Hrs) FROM dw.dimGhiPlanDaily GROUP BY Site, MonthOfYear")
        hsf = {(r[0], r[1]): float(r[2]) for r in cur.fetchall()}
    except Exception:
        return ["PR implicito: no se pudo leer dw.dimGhiPlanDaily; se omite la revision."]
    salidas = []
    for pl in sorted({p["Plantel"] for p in plan}):
        pis_pl = [p for p in pis if p["Plantel"] == pl]
        if any((p["CodigoSitio"], 1) not in hsf for p in pis_pl):
            salidas.append(f"PR implicito de '{pl}': faltan horas sol de algun sitio en dimGhiPlanDaily; se omite.")
            continue
        fuera = []
        for m in range(1, 13):
            kwh = next(p["PlanKwh"] for p in plan if p["Plantel"] == pl and p["Mes"] == m)
            base = sum(p["CapacidadDcKwp"] * hsf[(p["CodigoSitio"], m)] for p in pis_pl)
            pr = kwh / base if base else 0.0
            if not PR_MIN <= pr <= PR_MAX:
                fuera.append(f"mes {m}: {pr:.3f}")
        if fuera:
            salidas.append(f"PR implicito de '{pl}' fuera de {PR_MIN}-{PR_MAX} en {len(fuera)} mes(es) ({'; '.join(fuera)}). "
                           "Puede ser una fuente de irradiacion distinta a la de dimGhiPlanDaily, o un error de unidad; confirmar el origen del plan.")
    return salidas


# --- Carga (framework de control ETL) -----------------------------------------

def ejecutar_paso(conn, proceso, dominio, origen, destino, fn):
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
        proceso, dominio, origen[0], origen[0], origen[1], destino[0], destino[1], "FULL",
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


def cargar_stg_pi(pis, archivo):
    def fn(cur, run_id):
        cur.execute("TRUNCATE TABLE stg.dimPlantaSolar")
        cur.fast_executemany = True
        cur.executemany(
            "INSERT INTO stg.dimPlantaSolar (CodigoPI, Plantel, CodigoSitio, CapacidadDcKwp, CapacidadAcKw, ArchivoOrigen, RunId) VALUES (?,?,?,?,?,?,?)",
            [(p["CodigoPI"], p["Plantel"], p["CodigoSitio"], p["CapacidadDcKwp"], p["CapacidadAcKw"], archivo, run_id) for p in pis],
        )
        return len(pis), len(pis), 0, 0
    return fn


def cargar_stg_plan(plan, archivo, fuente, version):
    def fn(cur, run_id):
        cur.execute("TRUNCATE TABLE stg.dimPlanGeneracionMensual")
        cur.fast_executemany = True
        cur.executemany(
            "INSERT INTO stg.dimPlanGeneracionMensual (Anio, Mes, Plantel, PlanKwh, PlanFuente, PlanVersion, ArchivoOrigen, RunId) VALUES (?,?,?,?,?,?,?,?)",
            [(p["Anio"], p["Mes"], p["Plantel"], p["PlanKwh"], fuente, version, archivo, run_id) for p in plan],
        )
        return len(plan), len(plan), 0, 0
    return fn


def ejecutar_sp(sp):
    def fn(cur, run_id):
        cur.execute(f"EXEC {sp} @RunId = ?", run_id)
        return tuple(cur.fetchone())
    return fn


def main() -> int:
    parser = argparse.ArgumentParser(description="Carga masiva del plan de generacion de energia desde Excel.")
    parser.add_argument("--archivo", required=True, help="Ruta del Excel (hojas Plan_Anual y PI).")
    parser.add_argument("--version", required=True, help="Identificador de la version del plan (ej. V1, 2026-08-16).")
    parser.add_argument("--fuente", default=FUENTE_DEFECTO, help=f"Origen del plan (default: '{FUENTE_DEFECTO}').")
    parser.add_argument("--anio", type=int, default=None, help="Si se indica, exige que el plan sea de ese anio.")
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
    pis = leer_pi(wb, errores, avisos)
    if plan and pis:
        cruzar(plan, pis, errores, avisos)
    if args.anio and plan and plan[0]["Anio"] != args.anio:
        errores.append(f"El plan es del anio {plan[0]['Anio']} y se esperaba {args.anio}.")

    print(f"Archivo: {ruta.name} | version: {args.version} | fuente: {args.fuente}")
    if plan:
        print(f"Anio: {plan[0]['Anio']}")
        for pl in sorted({p['Plantel'] for p in plan}):
            print(f"  Plan {pl}: {sum(p['PlanKwh'] for p in plan if p['Plantel'] == pl):,.0f} kWh en el anio ({sum(1 for p in plan if p['Plantel'] == pl)} meses)")
    if pis:
        print(f"PI: {len(pis)} ({sum(p['CapacidadDcKwp'] for p in pis):,.2f} kWp DC en total)")

    conn = None
    if not errores:
        conn = build_connection(load_env(Path(args.env_file)))
        conn.autocommit = False
        avisos.extend(advertencia_pr(conn.cursor(), plan, pis))

    for a in avisos:
        print(f"AVISO: {a}")
    if errores:
        for e in errores:
            print(f"ERROR: {e}", file=sys.stderr)
        print("No se escribio nada en la base.", file=sys.stderr)
        return 2
    if args.dry_run:
        conn.close()
        print("Dry-run: validacion correcta, no se escribio nada.")
        return 0

    try:
        print("Cargando:")
        nombre = ruta.name
        pasos = [
            ("PlantaSolar_Bronze", ("Excel", "PI"), ("stg", "dimPlantaSolar"), cargar_stg_pi(pis, nombre)),
            ("PlanGeneracion_Bronze", ("Excel", "Plan_Anual"), ("stg", "dimPlanGeneracionMensual"), cargar_stg_plan(plan, nombre, args.fuente, args.version)),
            ("PlantaSolar_Silver", ("stg", "dimPlantaSolar"), ("int", "dimPlantaSolar"), ejecutar_sp("[int].usp_MergeDimPlantaSolar")),
            ("PlanGeneracion_Silver", ("stg", "dimPlanGeneracionMensual"), ("int", "dimPlanGeneracionMensual"), ejecutar_sp("[int].usp_MergeDimPlanGeneracionMensual")),
            ("PlantaSolar_Gold", ("int", "dimPlantaSolar"), ("dw", "dimPlantaSolar"), ejecutar_sp("dw.usp_MergeDimPlantaSolar")),
            ("PlanGeneracion_Gold", ("int", "dimPlanGeneracionMensual"), ("dw", "dimPlanGeneracionMensual"), ejecutar_sp("dw.usp_MergeDimPlanGeneracionMensual")),
        ]
        for proceso, origen, destino, fn in pasos:
            ejecutar_paso(conn, proceso, "PlanGeneracion", origen, destino, fn)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    print("Carga del plan de generacion completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
