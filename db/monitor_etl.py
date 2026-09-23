"""
Monitor del framework ETL de JAREMAR.

Consulta dbo.usp_Etl_AlertasObtener, imprime el reporte y, si hay alertas y
hay un canal configurado en el .env, notifica. Codigo de salida: 0 si no hay
alertas CRITICAS, 1 si hay (para que el scheduler tambien pueda alertar).

Uso:
    python db/monitor_etl.py                          # usa .env en la raiz
    python db/monitor_etl.py --env-file .env.prod
    python db/monitor_etl.py --env-file .env.prod --horas-sin-exito 30   # ademas alerta procesos sin exito en 30 h

Canales (todos opcionales; sin ninguno solo imprime):
    ALERT_WEBHOOK_URL    POST JSON {"text": "..."} (compatible con webhooks entrantes de Teams/Slack)
    ALERT_EMAIL_TO       destinatarios separados por coma (requiere ALERT_SMTP_HOST y ALERT_EMAIL_FROM)
    ALERT_SMTP_HOST, ALERT_SMTP_PORT (587), ALERT_SMTP_USER, ALERT_SMTP_PASSWORD, ALERT_EMAIL_FROM
    ALERT_SMTP_TLS       "0" para desactivar STARTTLS (por defecto activo)
"""
import argparse
import json
import smtplib
import sys
import urllib.request
from email.message import EmailMessage
from pathlib import Path

from migrate import ROOT, build_connection, load_env


def obtener_alertas(env: dict, args) -> list:
    cnxn = build_connection(env)
    try:
        cur = cnxn.cursor()
        cur.execute(
            "EXEC dbo.usp_Etl_AlertasObtener @HorasVentana = ?, @HorasEnProceso = ?, @HorasSinExito = ?",
            args.horas_ventana, args.horas_en_proceso, args.horas_sin_exito,
        )
        return [tuple(r) for r in cur.fetchall()]
    finally:
        cnxn.close()


def armar_reporte(alertas: list, env: dict) -> str:
    criticas = [a for a in alertas if a[0] == "CRITICA"]
    lineas = [
        f"ETL JAREMAR ({env.get('JAREMAR_SERVER', '?')}/{env.get('JAREMAR_DATABASE', '?')}): "
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(ROOT / ".env"))
    parser.add_argument("--horas-ventana", type=int, default=24, help="Ventana para errores/rechazos (default 24).")
    parser.add_argument("--horas-en-proceso", type=int, default=3, help="Corrida 'EN PROCESO' mas de N horas = colgada (default 3).")
    parser.add_argument("--horas-sin-exito", type=int, default=None, help="Alerta procesos sin exito en N horas (desactivado por defecto).")
    args = parser.parse_args()

    env = load_env(Path(args.env_file))
    alertas = obtener_alertas(env, args)

    if not alertas:
        print("Sin alertas.")
        return 0

    reporte = armar_reporte(alertas, env)
    print(reporte)

    hay_criticas = any(a[0] == "CRITICA" for a in alertas)
    asunto = f"[ETL JAREMAR] {'CRITICO' if hay_criticas else 'Advertencia'}: {len(alertas)} alerta(s)"

    if env.get("ALERT_WEBHOOK_URL"):
        try:
            notificar_webhook(env["ALERT_WEBHOOK_URL"], reporte)
            print("Notificado por webhook.")
        except Exception as exc:
            print(f"No se pudo notificar por webhook: {exc}", file=sys.stderr)

    if env.get("ALERT_EMAIL_TO") and env.get("ALERT_SMTP_HOST") and env.get("ALERT_EMAIL_FROM"):
        try:
            notificar_correo(env, asunto, reporte)
            print("Notificado por correo.")
        except Exception as exc:
            print(f"No se pudo notificar por correo: {exc}", file=sys.stderr)

    return 1 if hay_criticas else 0


if __name__ == "__main__":
    raise SystemExit(main())
