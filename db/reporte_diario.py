"""
Resumen diario por correo de todas las corridas del ETL (todos los dominios). Lo envia la tarea
JaremarDW-Resumen (db/scheduler/registrar_tareas_resumen.ps1) una vez al dia, aunque todo este bien.

Contenido, de las ultimas --horas (default 24) segun dbo.EtlRunLog:
  - Por dominio (dbo.EtlProcess.Dominio): corridas, con error, estado del ultimo run de cada proceso,
    ultima corrida, filas extraidas del origen (bronze), insertadas y actualizadas en gold (dw) y rechazadas.
  - Detalle de los errores del periodo (aunque despues se hayan recuperado).
  - Dominios sin ninguna corrida en el periodo (salvo las cargas manuales).
  - Alertas vigentes de dbo.usp_Etl_AlertasObtener (errores sin exito posterior, colgadas, rechazos, descuadres).

Los errores siguen avisandose al momento por el monitor de cada corrida; este correo es la confirmacion diaria.
Sale por los canales ALERT_* del .env (ver monitor_etl.py).

Uso:
    python db/reporte_diario.py --env-file .env.prod                                         # envia
    python db/reporte_diario.py --env-file .env.prod --vista-previa logs/reporte_diario.html  # no envia
"""
import argparse
import datetime
import html
import sys
from pathlib import Path

from migrate import ROOT, build_connection, load_env
from monitor_etl import canales_configurados, notificar, obtener_alertas
from reporte_solar import Crudo, tabla_html

# Dominios que no se programan (cargas manuales): no se reportan "sin corridas".
DOMINIOS_MANUALES = {"PlanGeneracion", "SinClasificar"}
LARGO_MENSAJE = 400


def miles(n) -> str:
    return "-" if n is None else f"{int(n):,}".replace(",", ".")


def consultar(env: dict, desde: datetime.datetime) -> dict:
    cnxn = build_connection(env)
    try:
        cur = cnxn.cursor()
        # Una fila por proceso con corridas en el periodo: totales y estado de su ultimo run.
        cur.execute("""
            WITH r AS (
                SELECT p.Dominio, p.ProcesoNombre, p.EsquemaDestino, r.RunId, r.FechaInicio, r.Estado, r.FilasLeidas,
                       r.FilasInsertadas, r.FilasActualizadas, r.FilasRechazadas, r.DuracionSegundos,
                       ROW_NUMBER() OVER (PARTITION BY r.ProcesoId ORDER BY r.RunId DESC) AS n
                FROM dbo.EtlRunLog r JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
                WHERE r.FechaInicio >= ?
            )
            SELECT Dominio, ProcesoNombre, COUNT(*),
                   SUM(CASE WHEN Estado = 'ERROR' THEN 1 ELSE 0 END),
                   MAX(CASE WHEN n = 1 THEN Estado END), MAX(FechaInicio),
                   SUM(CASE WHEN EsquemaDestino = 'stg' THEN CAST(FilasLeidas AS BIGINT) END),
                   SUM(CASE WHEN EsquemaDestino = 'dw' THEN CAST(FilasInsertadas AS BIGINT) END),
                   SUM(CASE WHEN EsquemaDestino = 'dw' THEN CAST(FilasActualizadas AS BIGINT) END),
                   SUM(CAST(FilasRechazadas AS BIGINT)),
                   SUM(DuracionSegundos)
            FROM r GROUP BY Dominio, ProcesoNombre""", desde)
        procesos = [tuple(f) for f in cur.fetchall()]
        cur.execute("""
            SELECT p.Dominio, p.ProcesoNombre, r.FechaInicio, r.TareaError, r.MensajeError
            FROM dbo.EtlRunLog r JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId
            WHERE r.FechaInicio >= ? AND r.Estado = 'ERROR' ORDER BY r.RunId""", desde)
        errores = [tuple(f) for f in cur.fetchall()]
        cur.execute("SELECT DISTINCT Dominio FROM dbo.EtlProcess WHERE Activo = 1")
        dominios = {f[0] for f in cur.fetchall()}
    finally:
        cnxn.close()
    horas = max(1, round((datetime.datetime.now() - desde).total_seconds() / 3600))
    args = argparse.Namespace(horas_ventana=horas, horas_en_proceso=3, horas_sin_exito=None,
                              procesos=None, dominios=None, alertas_solar=False, dias_sin_datos=None)
    alertas = obtener_alertas(env, args)
    return {"procesos": procesos, "errores": errores, "dominios": dominios, "alertas": alertas}


def por_dominio(procesos: list) -> list:
    """Agrega los procesos por dominio. Estado: ERROR si algun proceso termino su ultimo run en error,
    RECUPERADO si hubo errores pero el ultimo run de cada proceso fue bien."""
    grupos = {}
    for dom, _, corr, err, ult_estado, ult_fecha, lei, ins, act, rec, seg in procesos:
        g = grupos.setdefault(dom, {"dominio": dom, "procesos": 0, "corridas": 0, "errores": 0, "estados": set(),
                                    "ultima": None, "leidas": 0, "insertadas": 0, "actualizadas": 0,
                                    "rechazadas": 0, "segundos": 0})
        g["procesos"] += 1
        g["corridas"] += corr
        g["errores"] += err
        g["estados"].add(ult_estado)
        g["ultima"] = max(g["ultima"] or ult_fecha, ult_fecha)
        for clave, valor in (("leidas", lei), ("insertadas", ins), ("actualizadas", act), ("rechazadas", rec),
                             ("segundos", seg)):
            g[clave] += valor or 0
    for g in grupos.values():
        e = g["estados"]
        g["estado"] = ("ERROR" if "ERROR" in e else "EN PROCESO" if "EN PROCESO" in e else
                       "RECUPERADO" if g["errores"] else "ADVERTENCIA" if "ADVERTENCIA" in e else "OK")
    orden = {"ERROR": 0, "EN PROCESO": 1, "RECUPERADO": 2, "ADVERTENCIA": 3, "OK": 4}
    return sorted(grupos.values(), key=lambda g: (orden[g["estado"]], g["dominio"]))


def resumen(datos: dict) -> dict:
    grupos = por_dominio(datos["procesos"])
    con_corridas = {g["dominio"] for g in grupos}
    return {
        "grupos": grupos,
        "corridas": sum(g["corridas"] for g in grupos),
        "con_error": sum(g["errores"] for g in grupos),
        "dominios_error": [g["dominio"] for g in grupos if g["estado"] == "ERROR"],
        "sin_corridas": sorted(datos["dominios"] - con_corridas - DOMINIOS_MANUALES),
        "criticas": [a for a in datos["alertas"] if a[0] == "CRITICA"],
    }


def asunto(r: dict, ahora: datetime.datetime) -> str:
    base = f"[ETL JAREMAR] Resumen diario {ahora:%d/%m}: "
    if r["dominios_error"]:
        return base + f"ERRORES en {', '.join(r['dominios_error'])}"
    extra = []
    if r["con_error"]:
        extra.append(f"{r['con_error']} error(es) recuperado(s)")
    if r["sin_corridas"]:
        extra.append(f"{len(r['sin_corridas'])} dominio(s) sin corridas")
    if r["criticas"]:
        extra.append(f"{len(r['criticas'])} alerta(s)")
    return base + f"{r['corridas']} corridas OK" + (f" ({'; '.join(extra)})" if extra else "")


def armar_texto(datos: dict, r: dict, env: dict, desde: datetime.datetime, ahora: datetime.datetime) -> str:
    lineas = [f"ETL JAREMAR - resumen del {desde:%d/%m %H:%M} al {ahora:%d/%m %H:%M} "
              f"({env.get('JAREMAR_SERVER', '?')}/{env.get('JAREMAR_DATABASE', '?')})",
              f"Corridas: {r['corridas']}, con error: {r['con_error']}", ""]
    for g in r["grupos"]:
        lineas.append(f"  {g['dominio']:<16} {g['estado']:<11} corridas {g['corridas']:>3}  ultima {g['ultima']:%d/%m %H:%M}  "
                      f"extraidas {miles(g['leidas'])}  nuevas dw {miles(g['insertadas'])}  act dw {miles(g['actualizadas'])}  "
                      f"rech {miles(g['rechazadas'])}")
    if datos["errores"]:
        lineas += ["", "Errores del periodo:"]
        lineas += [f"  {d} / {p} {i:%d/%m %H:%M} [{t or '-'}]: {(m or '')[:LARGO_MENSAJE]}" for d, p, i, t, m in datos["errores"]]
    if r["sin_corridas"]:
        lineas += ["", f"Dominios sin corridas: {', '.join(r['sin_corridas'])}"]
    if datos["alertas"]:
        lineas += ["", "Alertas vigentes:"]
        lineas += [f"  [{s}] {t} - {p}: {d}" for s, t, p, _, _, d in datos["alertas"]]
    return "\n".join(lineas)


COLORES = {"ERROR": "#b00020", "EN PROCESO": "#b26a00", "RECUPERADO": "#b26a00", "ADVERTENCIA": "#b26a00", "OK": "#1b7f3b"}


def armar_html(datos: dict, r: dict, env: dict, desde: datetime.datetime, ahora: datetime.datetime) -> str:
    color = COLORES["ERROR"] if r["dominios_error"] else COLORES["OK"]
    estado = f"con errores en {', '.join(r['dominios_error'])}" if r["dominios_error"] else "sin errores pendientes"
    partes = [f"<h2 style='margin:0 0 4px 0'>ETL JAREMAR &ndash; resumen diario</h2>",
              f"<div style='color:#666;font-size:12px'>Del {desde:%d/%m/%Y %H:%M} al {ahora:%d/%m/%Y %H:%M} &middot; "
              f"{html.escape(env.get('JAREMAR_SERVER', '?'))} / {html.escape(env.get('JAREMAR_DATABASE', '?'))}</div>",
              f"<h3><span style='color:{color}'>{html.escape(estado)}</span> "
              f"<span style='font-weight:normal;font-size:13px'>({r['corridas']} corridas, {r['con_error']} con error)</span></h3>"]

    filas = [(g["dominio"], Crudo(f"<b style='color:{COLORES[g['estado']]}'>{g['estado']}</b>"), g["corridas"],
              g["errores"] or "-", g["procesos"], f"{g['ultima']:%d/%m %H:%M}", miles(g["leidas"]), miles(g["insertadas"]),
              miles(g["actualizadas"]), miles(g["rechazadas"]) if g["rechazadas"] else "-",
              f"{g['segundos'] / 60:.0f}") for g in r["grupos"]]
    partes.append(tabla_html(["Dominio", "Estado", "Corridas", "Con error", "Procesos", "Ultima", "Extraidas",
                              "Nuevas en dw", "Actualizadas en dw", "Rechazadas", "Minutos"], filas, {2, 3, 4, 6, 7, 8, 9, 10}))
    partes.append("<div style='color:#666;font-size:12px'>Estado = ultimo run de cada proceso del dominio. "
                  "RECUPERADO: hubo errores pero la corrida siguiente termino bien. Extraidas = filas leidas del origen "
                  "por los extract (bronze; los de Solar las deposita el proceso externo); nuevas y actualizadas = "
                  "cambios en gold (dw). Suman todas las corridas del periodo.</div>")

    if datos["errores"]:
        partes.append(f"<h3>Errores del periodo ({len(datos['errores'])})</h3>")
        partes.append(tabla_html(["Dominio", "Proceso", "Hora", "Tarea", "Mensaje"],
                                 [(d, p, f"{i:%d/%m %H:%M}", t or "-", (m or "")[:LARGO_MENSAJE])
                                  for d, p, i, t, m in datos["errores"]]))
    if r["sin_corridas"]:
        partes.append(f"<h3>Dominios sin corridas ({len(r['sin_corridas'])})</h3>"
                      f"<p>{html.escape(', '.join(r['sin_corridas']))}</p>"
                      "<div style='color:#666;font-size:12px'>Todos se programan al menos una vez al dia: si aparece "
                      "uno, su tarea no corrio.</div>")
    if datos["alertas"]:
        partes.append(f"<h3>Alertas vigentes ({len(datos['alertas'])})</h3>")
        partes.append(tabla_html(["Severidad", "Tipo", "Proceso", "Detalle"],
                                 [(s, t, p, d) for s, t, p, _, _, d in datos["alertas"]]))
    return ("<html><body style='font-family:Segoe UI,Arial,sans-serif;color:#222'>" + "\n".join(partes) + "</body></html>")


def main() -> int:
    parser = argparse.ArgumentParser(description="Resumen diario por correo de todas las corridas del ETL.")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--horas", type=int, default=24, help="Periodo a resumir, hacia atras desde ahora (default 24).")
    parser.add_argument("--vista-previa", metavar="ARCHIVO", help="Escribe el HTML en ARCHIVO y no envia nada.")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    ahora = datetime.datetime.now()
    desde = ahora - datetime.timedelta(hours=args.horas)
    try:
        datos = consultar(env, desde)
    except Exception as exc:
        texto = f"No se pudo consultar la base para el resumen diario: {exc}"
        print(texto, file=sys.stderr)
        if not args.vista_previa and any(canales_configurados(env).values()):
            notificar(env, f"[ETL JAREMAR] Resumen diario {ahora:%d/%m}: no se pudo consultar la base", texto)
        return 1

    r = resumen(datos)
    texto = armar_texto(datos, r, env, desde, ahora)
    print(asunto(r, ahora))
    print(texto)
    if args.vista_previa:
        Path(args.vista_previa).parent.mkdir(parents=True, exist_ok=True)
        Path(args.vista_previa).write_text(armar_html(datos, r, env, desde, ahora), encoding="utf-8")
        print(f"\nVista previa: {args.vista_previa}")
        return 0
    if not any(canales_configurados(env).values()):
        print("No hay canal configurado (ALERT_EMAIL_TO + ALERT_SMTP_HOST + ALERT_EMAIL_FROM); no se envia.", file=sys.stderr)
        return 1
    return 1 if notificar(env, asunto(r, ahora), texto, armar_html(datos, r, env, desde, ahora)) else 0


if __name__ == "__main__":
    raise SystemExit(main())
