"""
Monitor del framework ETL de JAREMAR.

Consulta dbo.usp_Etl_AlertasObtener, imprime el reporte y, si hay alertas y
hay un canal configurado en el .env, notifica. Codigo de salida: 0 si no hay
alertas CRITICAS, 1 si hay (para que el scheduler tambien pueda alertar).

Uso:
    python db/monitor_etl.py                          # usa .env en la raiz
    python db/monitor_etl.py --env-file .env.prod
    python db/monitor_etl.py --env-file .env.prod --horas-sin-exito 30   # ademas alerta procesos sin exito en 30 h

    # Solo los procesos de un dominio (prefijo del nombre del proceso), sin repetir el mismo aviso en 12 h:
    python db/monitor_etl.py --env-file .env.prod --procesos Sma Huawei Soliscloud Growatt Meteo --horas-sin-exito 16 --sin-repetir-horas 12

    # Comprobar que el canal de notificacion esta bien configurado (envia un mensaje de prueba y sale):
    python db/monitor_etl.py --env-file .env.prod --probar-notificacion

Canales (todos opcionales; sin ninguno solo imprime):
    ALERT_WEBHOOK_URL    POST JSON {"text": "..."} (compatible con webhooks entrantes de Teams/Slack)
    ALERT_EMAIL_TO       destinatarios separados por coma (requiere ALERT_SMTP_HOST y ALERT_EMAIL_FROM)
    ALERT_SMTP_HOST, ALERT_SMTP_PORT (587), ALERT_SMTP_USER, ALERT_SMTP_PASSWORD, ALERT_EMAIL_FROM
    ALERT_SMTP_TLS       "0" para desactivar STARTTLS (por defecto activo)
"""
import argparse
import datetime
import hashlib
import json
import smtplib
import sys
import urllib.request
from email.message import EmailMessage
from pathlib import Path

from migrate import ROOT, build_connection, load_env

ESTADO_DEFECTO = ROOT / "logs" / "monitor_estado.json"


def obtener_alertas(env: dict, args) -> list:
    cnxn = build_connection(env)
    try:
        cur = cnxn.cursor()
        cur.execute(
            "EXEC dbo.usp_Etl_AlertasObtener @HorasVentana = ?, @HorasEnProceso = ?, @HorasSinExito = ?",
            args.horas_ventana, args.horas_en_proceso, args.horas_sin_exito,
        )
        alertas = [tuple(r) for r in cur.fetchall()]
    finally:
        cnxn.close()
    if args.procesos:
        prefijos = tuple(p.lower() for p in args.procesos)
        alertas = [a for a in alertas if str(a[2]).lower().startswith(prefijos)]
    return alertas


def armar_reporte(alertas: list, env: dict, procesos: list = None) -> str:
    criticas = [a for a in alertas if a[0] == "CRITICA"]
    alcance = f" [{', '.join(procesos)}]" if procesos else ""
    lineas = [
        f"ETL JAREMAR{alcance} ({env.get('JAREMAR_SERVER', '?')}/{env.get('JAREMAR_DATABASE', '?')}): "
        f"{len(criticas)} critica(s), {len(alertas) - len(criticas)} advertencia(s)",
        "",
    ]
    for severidad, tipo, proceso, run_id, fecha, detalle in alertas:
        run = f"run {run_id}" if run_id is not None else "sin run"
        lineas.append(f"[{severidad}] {tipo} - {proceso} ({run}, {fecha:%Y-%m-%d %H:%M}): {detalle}")
    return "\n".join(lineas)


def notificar_webhook(url: str, reporte: str) -> None:
    req = urllib.request.Request(
        url, data=json.dumps({"text": reporte}).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    urllib.request.urlopen(req, timeout=15).read()


def notificar_correo(env: dict, asunto: str, reporte: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = asunto
    msg["From"] = env["ALERT_EMAIL_FROM"]
    msg["To"] = env["ALERT_EMAIL_TO"]
    msg.set_content(reporte)
    with smtplib.SMTP(env["ALERT_SMTP_HOST"], int(env.get("ALERT_SMTP_PORT", "587")), timeout=20) as smtp:
        if env.get("ALERT_SMTP_TLS", "1") != "0":
            smtp.starttls()
        if env.get("ALERT_SMTP_USER"):
            smtp.login(env["ALERT_SMTP_USER"], env.get("ALERT_SMTP_PASSWORD", ""))
        smtp.send_message(msg)


def canales_configurados(env: dict) -> dict:
    return {
        "webhook": bool(env.get("ALERT_WEBHOOK_URL")),
        "correo": bool(env.get("ALERT_EMAIL_TO") and env.get("ALERT_SMTP_HOST") and env.get("ALERT_EMAIL_FROM")),
    }


def notificar(env: dict, asunto: str, reporte: str) -> int:
    """Envia por los canales configurados. Devuelve cuantos canales fallaron."""
    fallos = 0
    canales = canales_configurados(env)
    if canales["webhook"]:
        try:
            notificar_webhook(env["ALERT_WEBHOOK_URL"], reporte)
            print("Notificado por webhook.")
        except Exception as exc:
            fallos += 1
            print(f"No se pudo notificar por webhook: {exc}", file=sys.stderr)
    if canales["correo"]:
        try:
            notificar_correo(env, asunto, reporte)
            print("Notificado por correo.")
        except Exception as exc:
            fallos += 1
            print(f"No se pudo notificar por correo: {exc}", file=sys.stderr)
    return fallos


# --- Supresion de avisos repetidos --------------------------------------------

def huella(alertas: list) -> str:
    base = sorted((a[0], a[1], str(a[2]), str(a[3])) for a in alertas)
    return hashlib.sha1(json.dumps(base).encode("utf-8")).hexdigest()


def clave_estado(args) -> str:
    return hashlib.sha1(("|".join(sorted(p.lower() for p in (args.procesos or ["*"])))).encode("utf-8")).hexdigest()[:12]


def leer_estado(ruta: Path) -> dict:
    try:
        return json.loads(ruta.read_text(encoding="utf-8"))
    except Exception:
        return {}


def guardar_estado(ruta: Path, estado: dict) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(json.dumps(estado, indent=1), encoding="utf-8")


def debe_notificar(args, alertas: list) -> bool:
    """False si es el mismo conjunto de alertas ya notificado dentro de --sin-repetir-horas."""
    if not args.sin_repetir_horas:
        return True
    ruta = Path(args.estado)
    estado = leer_estado(ruta)
    clave, ahora = clave_estado(args), datetime.datetime.now()
    previo = estado.get(clave)
    if previo and previo.get("huella") == huella(alertas):
        hace = (ahora - datetime.datetime.fromisoformat(previo["hora"])).total_seconds() / 3600
        if hace < args.sin_repetir_horas:
            return False
    estado[clave] = {"huella": huella(alertas), "hora": ahora.isoformat(timespec="seconds")}
    guardar_estado(ruta, estado)
    return True


def limpiar_estado(args) -> None:
    ruta = Path(args.estado)
    estado = leer_estado(ruta)
    if estado.pop(clave_estado(args), None) is not None:
        guardar_estado(ruta, estado)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--horas-ventana", type=int, default=24, help="Ventana para errores/rechazos (default 24).")
    parser.add_argument("--horas-en-proceso", type=int, default=3, help="Corrida 'EN PROCESO' mas de N horas = colgada (default 3).")
    parser.add_argument("--horas-sin-exito", type=int, default=None, help="Alerta procesos sin exito en N horas (desactivado por defecto).")
    parser.add_argument("--procesos", nargs="+", default=None, metavar="PREFIJO",
                        help="Solo considera los procesos cuyo nombre empieza por alguno de estos prefijos (ej. Sma Huawei).")
    parser.add_argument("--sin-repetir-horas", type=int, default=0,
                        help="No vuelve a notificar el mismo conjunto de alertas dentro de N horas (0 = siempre notifica).")
    parser.add_argument("--estado", default=str(ESTADO_DEFECTO), help="Archivo donde se recuerda el ultimo aviso (default logs/monitor_estado.json).")
    parser.add_argument("--probar-notificacion", action="store_true",
                        help="Envia un mensaje de prueba por los canales configurados y sale.")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))

    if args.probar_notificacion:
        canales = canales_configurados(env)
        if not any(canales.values()):
            print("No hay ningun canal configurado (ALERT_WEBHOOK_URL o ALERT_EMAIL_TO + ALERT_SMTP_HOST + ALERT_EMAIL_FROM).", file=sys.stderr)
            return 1
        print(f"Canales configurados: {[k for k, v in canales.items() if v]}")
        prueba = (f"Mensaje de prueba del monitor ETL JAREMAR ({env.get('JAREMAR_SERVER', '?')}/{env.get('JAREMAR_DATABASE', '?')}) "
                  f"- {datetime.datetime.now():%Y-%m-%d %H:%M}. Si lo recibes, las alertas estan bien configuradas.")
        return 1 if notificar(env, "[ETL JAREMAR] Prueba de notificacion", prueba) else 0

    alertas = obtener_alertas(env, args)

    if not alertas:
        print("Sin alertas.")
        if args.sin_repetir_horas:
            limpiar_estado(args)
        return 0

    reporte = armar_reporte(alertas, env, args.procesos)
    print(reporte)

    hay_criticas = any(a[0] == "CRITICA" for a in alertas)
    asunto = f"[ETL JAREMAR] {'CRITICO' if hay_criticas else 'Advertencia'}: {len(alertas)} alerta(s)"

    if debe_notificar(args, alertas):
        notificar(env, asunto, reporte)
    else:
        print(f"Mismas alertas ya notificadas hace menos de {args.sin_repetir_horas} h; no se reenvia.")

    return 1 if hay_criticas else 0


if __name__ == "__main__":
    raise SystemExit(main())
