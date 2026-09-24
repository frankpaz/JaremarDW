"""
Carga masiva del plan de generacion de energia desde el Excel del equipo de
planta ('Plan Produccion Energetica - Calculos.xlsx', hoja Sheet1) hacia
stg -> [int] -> dw.dimPlanGeneracion.

Lee las 9 columnas marcadas en verde de la hoja:
  Planta, Proveedor, Inversor (llave del dispositivo en el fabricante), InversorId,
  Mes, NombreMes, Ubicacion, PlanDiarioAsignado (plan diario de la PLANTA),
  PlanDiarioInversor (plan diario del inversor).
El archivo no trae anio: se indica con --anio y cada mes se expande a sus DIAS
REALES (una fila por fecha e inversor, igual que las versiones anteriores de la
tabla; las vistas del reporte leen ese grano). Si el archivo trae ademas
PlanTotalPlanta y PlanDiarioPlanta, comprueba que el divisor sea el numero de dias
del mes (avisa si se uso un divisor fijo, ej. /31).

Valida antes de escribir (cabeceras, Mes 1-12, valores numericos >= 0, sin
inversor-mes duplicado). Si hay errores no se escribe nada. Avisa, sin bloquear:
  * inversores sin plan (celda con error de Excel, vacia, o 0 en una planta sin plan asignado, ej. SOLIS): se omiten;
  * inversores con plan 0 mientras su planta tiene plan (capacidad faltante en el archivo);
  * plantas cuyos inversores suman menos que el plan de la planta;
  * dispositivos que no resuelven en las dimensiones (se cargan con llaves NULL).

Cada carga entra con una --version y queda en el historial: para cada fecha e
inversor queda vigente la version cargada mas recientemente; las fechas que la
nueva carga no trae conservan su version anterior. Recargar la misma version es
idempotente.

Si un archivo NUEVO redefine por completo a uno anterior (p.ej. cambia el formato o el nombre
con que se identifica cada inversor), --reemplaza-version deja esas versiones como historicas
(EsVigente = 0) aunque el nuevo archivo no cubra exactamente las mismas filas.

Requiere openpyxl (solo para este cargador).

Uso:
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --anio 2026 --version V2 --dry-run
    python db/etl/dimPlanGeneracion/cargar_plan_generacion.py --archivo "<ruta>.xlsx" --anio 2026 --version V2 [--hoja Sheet1] [--fuente "..."] [--env-file .env.prod]
"""
import argparse
import calendar
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

HOJA_DEFECTO = "Sheet1"
FUENTE_DEFECTO = "Plan Produccion Energetica - Calculos"
REQUERIDAS = ["PLANTA", "PROVEEDOR", "INVERSOR", "INVERSORID", "MES", "NOMBREMES", "UBICACION",
              "PLANDIARIOASIGNADO", "PLANDIARIOINVERSOR"]
TOLERANCIA_REPARTO = 0.005  # 0.5 %


def norm(texto) -> str:
    s = unicodedata.normalize("NFD", str(texto or ""))
    return "".join(c for c in s if unicodedata.category(c) != "Mn").strip().upper()


def es_error_excel(v) -> bool:
    return isinstance(v, str) and v.strip().startswith("#")


def es_numero(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


# --- Lectura y validacion del Excel ------------------------------------------

def leer_filas(wb, hoja, errores: list, avisos: list) -> list:
    if hoja not in wb.sheetnames:
        errores.append(f"No existe la hoja '{hoja}'. Hojas: {wb.sheetnames}")
        return []
    filas = list(wb[hoja].iter_rows(values_only=True))
    if not filas:
        errores.append(f"La hoja '{hoja}' esta vacia.")
        return []
    cab = {norm(c): j for j, c in enumerate(filas[0]) if c is not None}
    faltan = [c for c in REQUERIDAS if c not in cab]
    if faltan:
        errores.append(f"Faltan las columnas {faltan} en la primera fila de '{hoja}'.")
        return []
    g = lambda r, k: r[cab[k]] if cab[k] < len(r) else None
    tiene_diario = "PLANTOTALPLANTA" in cab and "PLANDIARIOPLANTA" in cab

    resultado, vistos = [], set()
    for n, r in enumerate(filas[1:], start=2):
        if r is None or all(v is None for v in r):
            continue
        planta, prov, disp, iid = (str(g(r, k) or "").strip() for k in ("PLANTA", "PROVEEDOR", "INVERSOR", "INVERSORID"))
        if not (planta and prov and disp and iid):
            errores.append(f"'{hoja}' fila {n}: Planta, Proveedor, Inversor e InversorId son obligatorios.")
            continue
        mes = g(r, "MES")
        if not es_numero(mes) or int(mes) != mes or not 1 <= int(mes) <= 12:
            errores.append(f"'{hoja}' fila {n} ({iid}): Mes invalido {mes!r}.")
            continue
        mes = int(mes)
        if (iid, mes) in vistos:
            errores.append(f"'{hoja}' fila {n}: el inversor {iid} tiene el mes {mes} duplicado.")
            continue
        vistos.add((iid, mes))
        plan_inv, plan_asig = g(r, "PLANDIARIOINVERSOR"), g(r, "PLANDIARIOASIGNADO")
        for nombre, v in (("PlanDiarioInversor", plan_inv), ("PlanDiarioAsignado", plan_asig)):
            if not (es_numero(v) or es_error_excel(v) or v is None):
                errores.append(f"'{hoja}' fila {n} ({iid}), {nombre}: valor no numerico {v!r}.")
            elif es_numero(v) and v < 0:
                errores.append(f"'{hoja}' fila {n} ({iid}), {nombre}: valor negativo {v}.")
        dias_impl = None
        if tiene_diario and es_numero(g(r, "PLANTOTALPLANTA")) and es_numero(g(r, "PLANDIARIOPLANTA")) and g(r, "PLANDIARIOPLANTA"):
            dias_impl = g(r, "PLANTOTALPLANTA") / g(r, "PLANDIARIOPLANTA")
        resultado.append({
            "fila": n, "Planta": planta, "Proveedor": prov.lower(), "DispositivoId": disp, "CodigoInversor": iid,
            "Mes": mes, "NombreMes": str(g(r, "NOMBREMES") or "").strip() or None,
            "Ubicacion": str(g(r, "UBICACION") or "").strip() or None,
            "PlanDiarioAsignado": plan_asig, "PlanDiarioInversor": plan_inv, "DiasImplicitos": dias_impl,
        })
    if not resultado:
        errores.append(f"'{hoja}' no tiene filas de datos.")
    return resultado


def evaluar_calidad(filas: list, anio: int, avisos: list) -> list:
    """Devuelve las filas que se cargan y agrega los avisos de calidad."""
    malos = sorted({f["Mes"] for f in filas if f["DiasImplicitos"] is not None
                    and abs(f["DiasImplicitos"] - calendar.monthrange(anio, f["Mes"])[1]) > 0.01})
    if malos:
        avisos.append(f"PlanDiarioPlanta no corresponde a los dias reales de {anio} en los meses {malos} "
                      "(PlanTotalPlanta / PlanDiarioPlanta no es el numero de dias del mes; posible divisor fijo).")

    cargar, error_inv, cero_inv = [], {}, {}
    for f in filas:
        pi, pa = f["PlanDiarioInversor"], f["PlanDiarioAsignado"]
        sin_plan = es_error_excel(pi) or pi is None or (es_numero(pi) and pi == 0 and (not es_numero(pa) or pa == 0))
        if sin_plan:
            error_inv.setdefault((f["Planta"], f["CodigoInversor"]), []).append(f["Mes"])
            continue
        f["PlanDiarioAsignado"] = float(pa) if es_numero(pa) else None
        if pi == 0 and es_numero(pa) and pa > 0:
            cero_inv.setdefault(f["Planta"], set()).add(f["CodigoInversor"])
        cargar.append(f)
    for (planta, inv), meses in sorted(error_inv.items()):
        avisos.append(f"{planta} / {inv}: sin plan en {len(meses)} mes(es) (error de Excel, vacio, o 0 con la planta sin plan asignado); se omite.")
    for planta, invs in sorted(cero_inv.items()):
        avisos.append(f"{planta}: {len(invs)} inversor(es) con plan 0 aunque la planta tiene plan asignado "
                      f"({sorted(invs)}); suele ser capacidad faltante en el archivo.")

    por = {}
    for f in cargar:
        d = por.setdefault((f["Planta"], f["Mes"]), {"asig": f["PlanDiarioAsignado"], "suma": 0.0})
        d["suma"] += float(f["PlanDiarioInversor"])
    resumen = {}
    for (planta, mes), d in por.items():
        if d["asig"]:
            r = resumen.setdefault(planta, [0.0, 0.0])
            r[0] += d["suma"]
            r[1] += d["asig"]
    for planta, (suma, asig) in sorted(resumen.items()):
        if asig and abs(suma / asig - 1) > TOLERANCIA_REPARTO:
            avisos.append(f"{planta}: los inversores suman {suma / asig:.1%} del plan diario de la planta "
                          f"(el resto no esta repartido). El plan de la planta se toma de PlanDiarioAsignado.")
    return cargar


def expandir_dias(filas: list, anio: int) -> list:
    salida = []
    for f in filas:
        for dia in range(1, calendar.monthrange(anio, f["Mes"])[1] + 1):
            salida.append({**f, "Fecha": datetime.date(anio, f["Mes"], dia)})
    return salida


def avisar_dispositivos(cur, filas: list, avisos: list) -> None:
    """Dispositivos (Proveedor + Inversor) que no resuelven en su dimension."""
    consultas = {
        "sma": "SELECT CAST(DeviceId AS NVARCHAR(50)) FROM dw.dimSmaDevices",
        "huawei": "SELECT CAST(DeviceId AS NVARCHAR(50)) FROM dw.dimHuaweiDevices",
        "soliscloud": "SELECT DeviceSn FROM dw.dimSoliscloudDevices",
        "growatt": "SELECT JoinKey FROM dw.dimDeviceCapacity WHERE JoinKey IS NOT NULL",
    }
    try:
        conocidos = {}
        for prov, sql in consultas.items():
            cur.execute(sql)
            conocidos[prov] = {str(r[0]).strip() for r in cur.fetchall() if r[0] is not None}
    except Exception:
        avisos.append("No se pudieron leer las dimensiones de dispositivos; se omite la revision.")
        return
    sin = sorted({(f["Proveedor"], f["CodigoInversor"]) for f in filas
                  if f["DispositivoId"] not in conocidos.get(f["Proveedor"], set())})
    if sin:
        avisos.append(f"{len(sin)} inversor(es) sin match en la dimension de su fabricante: {sin}. "
                      "Se cargan con las llaves de dispositivo en NULL.")


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
            "INSERT INTO stg.dimPlanGeneracion (Fecha, CodigoInversor, PlanKwh, PlanFuente, PlanVersion, ArchivoOrigen, "
            "Planta, Proveedor, DispositivoId, Ubicacion, Mes, NombreMes, PlanDiarioAsignado, RunId) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [(p["Fecha"], p["CodigoInversor"], round(float(p["PlanDiarioInversor"]), 8), fuente, version, archivo,
              p["Planta"], p["Proveedor"], p["DispositivoId"], p["Ubicacion"], p["Mes"], p["NombreMes"],
              None if p["PlanDiarioAsignado"] is None else round(p["PlanDiarioAsignado"], 8), run_id) for p in plan],
        )
        return len(plan), len(plan), 0, 0
    return fn


def retirar_versiones(versiones, version_nueva):
    """Marca como historicas TODAS las filas de las versiones indicadas (silver; gold lo hereda en su merge)."""
    def fn(cur, run_id):
        n = 0
        for v in versiones:
            if v == version_nueva:
                continue
            cur.execute("UPDATE [int].dimPlanGeneracion SET EsVigente = 0, FechaCargaInt = SYSDATETIME(), RunId = ? "
                        "WHERE PlanVersion = ? AND EsVigente = 1", run_id, v)
            n += cur.rowcount
        return n, 0, n, 0
    return fn


def ejecutar_sp(sp):
    def fn(cur, run_id):
        cur.execute(f"EXEC {sp} @RunId = ?", run_id)
        return tuple(cur.fetchone())
    return fn


def main() -> int:
    parser = argparse.ArgumentParser(description="Carga masiva del plan de generacion de energia (Sheet1 de Calculos) desde Excel.")
    parser.add_argument("--archivo", required=True, help="Ruta del Excel.")
    parser.add_argument("--anio", required=True, type=int, help="Anio del plan (el archivo trae solo el mes).")
    parser.add_argument("--version", required=True, help="Identificador de la version del plan (ej. V2, 2026-09-23).")
    parser.add_argument("--reemplaza-version", nargs="+", default=[], metavar="VERSION",
                        help="Versiones anteriores que esta carga reemplaza por completo (quedan como historicas).")
    parser.add_argument("--hoja", default=HOJA_DEFECTO, help=f"Hoja a leer (default: {HOJA_DEFECTO}).")
    parser.add_argument("--fuente", default=FUENTE_DEFECTO, help=f"Origen del plan (default: '{FUENTE_DEFECTO}').")
    parser.add_argument("--dry-run", action="store_true", help="Solo valida y muestra el resumen; no escribe en la base.")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    args = parser.parse_args()

    ruta = Path(args.archivo)
    if not ruta.is_file():
        print(f"ERROR: no existe el archivo {ruta}", file=sys.stderr)
        return 2

    wb = openpyxl.load_workbook(ruta, data_only=True)
    errores, avisos = [], []
    filas = leer_filas(wb, args.hoja, errores, avisos)
    plan = []
    if filas and not errores:
        cargables = evaluar_calidad(filas, args.anio, avisos)
        plan = expandir_dias(cargables, args.anio)

    print(f"Archivo: {ruta.name} | hoja: {args.hoja} | anio: {args.anio} | version: {args.version} | fuente: {args.fuente}")
    if plan:
        inv = {(p["Proveedor"], p["CodigoInversor"]) for p in plan}
        print(f"Fechas: {plan[0]['Fecha']} a {plan[-1]['Fecha']} | plantas: {len({p['Planta'] for p in plan})} | inversores: {len(inv)} | filas: {len(plan)}")
        print(f"Plan de inversores: {sum(p['PlanDiarioInversor'] for p in plan):,.0f} kWh en el anio")

    conn = None
    if not errores and plan:
        conn = build_connection(load_env(Path(args.env_file)))
        conn.autocommit = False
        avisar_dispositivos(conn.cursor(), plan, avisos)

    for a in avisos:
        print(f"AVISO: {a}")
    if errores:
        for e in errores:
            print(f"ERROR: {e}", file=sys.stderr)
        print("No se escribio nada en la base.", file=sys.stderr)
        return 2
    if not plan:
        print("ERROR: no quedaron filas de plan para cargar.", file=sys.stderr)
        return 2
    if args.dry_run:
        conn.close()
        print("Dry-run: validacion correcta, no se escribio nada.")
        return 0

    try:
        print("Cargando:")
        nombre = ruta.name
        pasos = [
            ("PlanGeneracion_Bronze", ("Excel", args.hoja), ("stg", "dimPlanGeneracion"), cargar_stg(plan, nombre, args.fuente, args.version)),
            ("PlanGeneracion_Silver", ("stg", "dimPlanGeneracion"), ("int", "dimPlanGeneracion"), ejecutar_sp("[int].usp_MergeDimPlanGeneracion")),
            ("PlanGeneracion_Gold", ("int", "dimPlanGeneracion"), ("dw", "dimPlanGeneracion"), ejecutar_sp("dw.usp_MergeDimPlanGeneracion")),
        ]
        if args.reemplaza_version:
            pasos.insert(2, ("PlanGeneracion_Reemplazo", ("int", "dimPlanGeneracion"), ("int", "dimPlanGeneracion"),
                             retirar_versiones(args.reemplaza_version, args.version)))
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
