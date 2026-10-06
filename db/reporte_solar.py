"""
Reporte por correo del dominio Solar. Lo envia db/scheduler/run_solar.py al final de cada corrida:

  - Diario: en la primera corrida del dia desde la hora de reporte (default 10:00), aunque todo este bien.
    Si un dia no llega, la tarea no corrio (el vigilante tambien avisa).
  - Inmediato: en cualquier corrida con pasos fallidos, con el detalle del error.

Contenido: estado de la corrida (pasos con error y las ultimas lineas de su salida, errores registrados en
dbo.EtlRunLog), inversores sin produccion (dw.usp_SolarInversoresSinProduccion: 2 o mas dias seguidos sin
dato o en 0 kWh, hasta ayer) y las demas alertas del monitor acotadas a Solar. Sale por los canales ALERT_*
del .env (ver monitor_etl.py): el correo lleva HTML y texto; el webhook, el texto.

Uso manual (pruebas):
    python db/reporte_solar.py --env-file .env.prod --vista-previa logs/reporte_solar.html   # escribe el HTML, no envia
    python db/reporte_solar.py --env-file .env.prod --enviar                                  # envia el reporte diario ahora
"""
import argparse
import datetime
import html
import json
import sys
from pathlib import Path

from migrate import ROOT, build_connection, load_env
from monitor_etl import canales_configurados, notificar, obtener_alertas

ESTADO_DEFECTO = ROOT / "logs" / "reporte_solar_estado.json"
HORA_REPORTE_DEFECTO = 10
DIAS_SEGUIDOS = 2      # inversores con 2 o mas dias seguidos sin produccion
DIAS_VENTANA = 30      # "dias sin produccion" se cuenta en los ultimos 30 dias
LINEAS_SALIDA = 12     # ultimas lineas de la salida de un paso fallido


# --- Datos -----------------------------------------------------------------------

def consultar(env: dict, prefijos: list, desde: datetime.datetime = None, horas_sin_exito: int = 16) -> dict:
    """Inversores sin produccion, errores de la corrida (dbo.EtlRunLog desde `desde`) y demas alertas.
    Si la base no responde, devuelve listas vacias y el motivo en 'problema'."""
    datos = {"inversores": [], "errores": [], "alertas": [], "problema": None}
    try:
        cnxn = build_connection(env)
        try:
            cur = cnxn.cursor()
            cur.execute("EXEC dw.usp_SolarInversoresSinProduccion @DiasSeguidosMin = ?, @DiasVentana = ?",
                        DIAS_SEGUIDOS, DIAS_VENTANA)
            datos["inversores"] = [tuple(r) for r in cur.fetchall()]
            if desde is not None:
                filtro = " OR ".join("p.ProcesoNombre LIKE ?" for _ in prefijos)
                cur.execute(
                    "SELECT p.ProcesoNombre, r.FechaInicio, r.TareaError, r.MensajeError "
                    "FROM dbo.EtlRunLog r JOIN dbo.EtlProcess p ON p.ProcesoId = r.ProcesoId "
                    f"WHERE r.Estado = 'ERROR' AND r.FechaInicio >= ? AND ({filtro}) ORDER BY r.RunId",
                    desde, *[f"{p}%" for p in prefijos],
                )
                datos["errores"] = [tuple(r) for r in cur.fetchall()]
        finally:
            cnxn.close()
        args = argparse.Namespace(horas_ventana=24, horas_en_proceso=3, horas_sin_exito=horas_sin_exito,
                                  procesos=prefijos, dominios=None, alertas_solar=True, dias_sin_datos=DIAS_SEGUIDOS)
        # INVERSOR_SIN_DATOS es lo mismo que la tabla de inversores: no se repite
        datos["alertas"] = [a for a in obtener_alertas(env, args) if a[1] != "INVERSOR_SIN_DATOS"]
    except Exception as exc:
        datos["problema"] = str(exc)
    return datos


def situacion(ultima_produccion, ultimo_dato, hoy: datetime.date = None) -> str:
    """Por que no hay produccion: el portal reporta el equipo en 0, o dejaron de llegar datos."""
    if ultimo_dato is None:
        return "Nunca ha tenido datos"
    ayer = (hoy or datetime.date.today()) - datetime.timedelta(days=1)
    if ultimo_dato >= ayer:
        return "Reporta 0 kWh"
    texto = f"No llegan datos desde el {ultimo_dato + datetime.timedelta(days=1):%d/%m/%Y}"
    if ultima_produccion is None or ultimo_dato > ultima_produccion:
        texto += " (antes reportaba 0 kWh)"
    return texto


# --- Armado ----------------------------------------------------------------------

def fecha(valor) -> str:
    return "nunca" if valor is None else f"{valor:%d/%m/%Y}"


def asunto(resultados: list, datos: dict) -> str:
    fallidos = [r for r in resultados if r["estado"] == "FALLO"]
    if fallidos:
        return f"[ETL JAREMAR] Solar: CORRIDA CON ERRORES ({len(fallidos)} paso(s))"
    if datos["problema"]:
        return "[ETL JAREMAR] Solar: no se pudo consultar la base"
    n = len(datos["inversores"])
    return f"[ETL JAREMAR] Solar: reporte diario - {n} inversor(es) sin produccion" if n else \
           "[ETL JAREMAR] Solar: reporte diario - sin novedades"


def armar_texto(resultados: list, datos: dict, env: dict, ahora: datetime.datetime, ruta_log: str = None) -> str:
    fallidos = [r for r in resultados if r["estado"] == "FALLO"]
    lineas = [f"Dominio Solar - {ahora:%d/%m/%Y %H:%M} ({env.get('JAREMAR_SERVER', '?')}/{env.get('JAREMAR_DATABASE', '?')})", ""]
    if resultados:
        ok = sum(1 for r in resultados if r["estado"] == "OK")
        lineas.append(f"Corrida: {'CON ERRORES' if fallidos else 'sin errores'} ({ok}/{len(resultados)} pasos OK)")
    for r in fallidos:
        lineas.append(f"  FALLO {r['grupo']} / {r['paso']} (rc={r['rc']})")
        lineas += [f"    {l}" for l in r.get("salida", "").strip().splitlines()[-LINEAS_SALIDA:]]
    for proceso, inicio, tarea, mensaje in datos["errores"]:
        lineas.append(f"  ERROR {proceso} {inicio:%H:%M} [{tarea or '-'}]: {mensaje or ''}")
    if datos["problema"]:
        lineas.append(f"No se pudo consultar la base: {datos['problema']}")
    lineas += ["", f"Inversores con {DIAS_SEGUIDOS} o mas dias seguidos sin produccion (sin dato o 0 kWh, hasta ayer): "
                   f"{len(datos['inversores'])}"]
    for planta, inversor, proveedor, ult_prod, ult_dato, seguidos, en_ventana in datos["inversores"]:
        lineas.append(f"  {planta} {inversor} ({proveedor}): ultima produccion {fecha(ult_prod)}, "
                      f"{seguidos if seguidos is not None else '-'} dias seguidos, {en_ventana if en_ventana is not None else '-'} "
                      f"de {DIAS_VENTANA} dias; {situacion(ult_prod, ult_dato)}")
    if datos["alertas"]:
        lineas += ["", "Otras alertas:"]
        lineas += [f"  [{s}] {t} - {p}: {d}" for s, t, p, _, _, d in datos["alertas"]]
    if ruta_log:
        lineas += ["", f"Registro de la corrida: {ruta_log}"]
    return "\n".join(lineas)


ESTILO_TABLA = "border-collapse:collapse;font-size:13px;margin:6px 0 14px 0"
ESTILO_TH = "border:1px solid #c8c8c8;background:#f0f0f0;padding:4px 8px;text-align:left"
ESTILO_TD = "border:1px solid #c8c8c8;padding:4px 8px;vertical-align:top"


class Crudo(str):
    """Texto HTML ya armado (no se escapa)."""


def tabla_html(encabezados: list, filas: list, numericas: set = frozenset()) -> str:
    th = "".join(f'<th style="{ESTILO_TH}">{html.escape(h)}</th>' for h in encabezados)
    cuerpo = []
    for fila in filas:
        celdas = []
        for i, valor in enumerate(fila):
            alinear = ";text-align:right" if i in numericas else ""
            contenido = valor if isinstance(valor, Crudo) else html.escape("" if valor is None else str(valor))
            celdas.append(f'<td style="{ESTILO_TD}{alinear}">{contenido}</td>')
        cuerpo.append(f"<tr>{''.join(celdas)}</tr>")
    return f'<table style="{ESTILO_TABLA}"><tr>{th}</tr>{"".join(cuerpo)}</table>'


def armar_html(resultados: list, datos: dict, env: dict, ahora: datetime.datetime, ruta_log: str = None) -> str:
    fallidos = [r for r in resultados if r["estado"] == "FALLO"]
    partes = [f"<h2 style='margin:0 0 4px 0'>Dominio Solar &ndash; {ahora:%d/%m/%Y %H:%M}</h2>",
              f"<div style='color:#666;font-size:12px'>{html.escape(env.get('JAREMAR_SERVER', '?'))} / "
              f"{html.escape(env.get('JAREMAR_DATABASE', '?'))}</div>"]

    # Corrida
    if resultados:
        ok = sum(1 for r in resultados if r["estado"] == "OK")
        color, texto = ("#b00020", "CON ERRORES") if fallidos else ("#1b7f3b", "sin errores")
        partes.append(f"<h3>Corrida: <span style='color:{color}'>{texto}</span> "
                      f"<span style='font-weight:normal;font-size:13px'>({ok} de {len(resultados)} pasos OK)</span></h3>")
        por_grupo = {}
        for r in resultados:
            por_grupo.setdefault(r["grupo"], []).append(r)
        filas = []
        for grupo, pasos in por_grupo.items():
            malos = [p["paso"] for p in pasos if p["estado"] == "FALLO"]
            omitidos = sum(1 for p in pasos if p["estado"] == "OMITIDO")
            filas.append((grupo, f"{sum(1 for p in pasos if p['estado'] == 'OK')}/{len(pasos)}",
                          ", ".join(malos) or "-", omitidos or "-"))
        partes.append(tabla_html(["Grupo", "Pasos OK", "Fallo en", "Omitidos"], filas, {1, 3}))
    if fallidos:
        partes.append("<h4 style='margin-bottom:0'>Detalle de los pasos con error</h4>")
        filas = [(r["grupo"], r["paso"], r["rc"],
                  Crudo("<pre style='margin:0;font-size:12px;white-space:pre-wrap'>"
                        + html.escape("\n".join(r.get("salida", "").strip().splitlines()[-LINEAS_SALIDA:])) + "</pre>"))
                 for r in fallidos]
        partes.append(tabla_html(["Grupo", "Paso", "Codigo", "Ultimas lineas de la salida"], filas, {2}))
    if datos["errores"]:
        partes.append("<h4 style='margin-bottom:0'>Errores registrados en la base (dbo.EtlRunLog)</h4>")
        filas = [(p, f"{i:%H:%M:%S}", t or "-", m or "") for p, i, t, m in datos["errores"]]
        partes.append(tabla_html(["Proceso", "Hora", "Tarea", "Mensaje"], filas))
    if datos["problema"]:
        partes.append(f"<p style='color:#b00020'><b>No se pudo consultar la base:</b> {html.escape(datos['problema'])}</p>")

    # Inversores
    partes.append(f"<h3>Inversores sin produccion ({len(datos['inversores'])})</h3>")
    if datos["inversores"]:
        filas = [(pl, inv, prov, fecha(up), seg, ven, situacion(up, ud))
                 for pl, inv, prov, up, ud, seg, ven in datos["inversores"]]
        partes.append(tabla_html(["Planta", "Inversor", "Proveedor", "Ultima produccion", "Dias seguidos sin produccion",
                                  f"Dias sin produccion (ultimos {DIAS_VENTANA})", "Situacion"], filas, {4, 5}))
    elif not datos["problema"]:
        partes.append("<p>Todos los inversores del informe produjeron ayer o anteayer.</p>")
    partes.append(f"<div style='color:#666;font-size:12px'>Sin produccion = dia sin dato o con 0 kWh, contado desde el "
                  f"primer dato del inversor y hasta ayer. Se listan los que llevan {DIAS_SEGUIDOS} o mas dias seguidos. "
                  f"Huawei solo trae el total diario.</div>")

    # Otras alertas
    if datos["alertas"]:
        partes.append(f"<h3>Otras alertas ({len(datos['alertas'])})</h3>")
        partes.append(tabla_html(["Severidad", "Tipo", "Proceso", "Detalle"], [(s, t, p, d) for s, t, p, _, _, d in datos["alertas"]]))

    if ruta_log:
        partes.append(f"<p style='color:#666;font-size:12px'>Registro de la corrida: {html.escape(str(ruta_log))}</p>")
    return ("<html><body style='font-family:Segoe UI,Arial,sans-serif;color:#222'>" + "\n".join(partes) + "</body></html>")


# --- Cuando enviar ---------------------------------------------------------------

def leer_estado(ruta: Path) -> dict:
    try:
        return json.loads(ruta.read_text(encoding="utf-8"))
    except Exception:
        return {}


def diario_pendiente(ahora: datetime.datetime, hora_reporte: int, ruta: Path) -> bool:
    return ahora.hour >= hora_reporte and leer_estado(ruta).get("ultimo_diario") != ahora.date().isoformat()


def marcar_diario(ahora: datetime.datetime, ruta: Path) -> None:
    estado = leer_estado(ruta)
    estado["ultimo_diario"] = ahora.date().isoformat()
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(json.dumps(estado, indent=1), encoding="utf-8")


def reportar_corrida(env: dict, resultados: list, inicio: datetime.datetime, prefijos: list, log=print,
                     hora_reporte: int = HORA_REPORTE_DEFECTO, horas_sin_exito: int = 16, ruta_log: str = None,
                     forzar_diario: bool = False, estado: Path = ESTADO_DEFECTO) -> bool:
    """Envia el reporte si corresponde (diario pendiente o pasos fallidos). Devuelve True si lo envio."""
    ahora = datetime.datetime.now()
    hubo_fallo = any(r["estado"] == "FALLO" for r in resultados)
    diario = forzar_diario or diario_pendiente(ahora, hora_reporte, estado)
    if not (hubo_fallo or diario):
        log("Reporte Solar: sin fallos y el diario ya se envio hoy (o aun no son las "
            f"{hora_reporte}:00); no se envia.")
        return False
    if not any(canales_configurados(env).values()):
        log("Reporte Solar: no hay canal configurado (ALERT_EMAIL_TO + ALERT_SMTP_HOST + ALERT_EMAIL_FROM); no se envia.")
        return False
    datos = consultar(env, prefijos, inicio, horas_sin_exito)
    fallos = notificar(env, asunto(resultados, datos), armar_texto(resultados, datos, env, ahora, ruta_log),
                       armar_html(resultados, datos, env, ahora, ruta_log))
    if fallos:
        log(f"Reporte Solar: fallo el envio por {fallos} canal(es).")
        return False
    if diario:
        marcar_diario(ahora, estado)
    log(f"Reporte Solar enviado ({'diario' if diario else ''}{' + ' if diario and hubo_fallo else ''}"
        f"{'errores' if hubo_fallo else ''}): {len(datos['inversores'])} inversor(es) sin produccion, "
        f"{len(datos['errores'])} error(es) registrados, {len(datos['alertas'])} otra(s) alerta(s).")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Reporte por correo del dominio Solar (pruebas; lo envia run_solar.py).")
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--vista-previa", metavar="ARCHIVO", help="Escribe el HTML en ARCHIVO y no envia nada.")
    parser.add_argument("--enviar", action="store_true", help="Envia ahora el reporte diario (no marca el diario como enviado).")
    args = parser.parse_args()
    if not (args.vista_previa or args.enviar):
        parser.error("indica --vista-previa ARCHIVO o --enviar")

    sys.path.insert(0, str(ROOT / "db" / "scheduler"))
    from run_solar import HORAS_SIN_EXITO, PREFIJOS_MONITOR  # noqa: E402

    env = load_env(Path(args.env_file))
    ahora = datetime.datetime.now()
    datos = consultar(env, PREFIJOS_MONITOR, None, HORAS_SIN_EXITO)
    if datos["problema"]:
        print(f"No se pudo consultar la base: {datos['problema']}", file=sys.stderr)
    print(armar_texto([], datos, env, ahora))
    if args.vista_previa:
        Path(args.vista_previa).write_text(armar_html([], datos, env, ahora), encoding="utf-8")
        print(f"\nVista previa: {args.vista_previa}")
        return 0
    return 1 if notificar(env, asunto([], datos), armar_texto([], datos, env, ahora), armar_html([], datos, env, ahora)) else 0


if __name__ == "__main__":
    raise SystemExit(main())
