"""Publish deployment hints after CI has uploaded the selected revision."""

import os
import threading
import uuid

import paho.mqtt.client as mqtt


def main():
    connected = threading.Event()
    connection_result = []
    publish_results = {}

    def on_connect(client, userdata, flags, reason_code, properties):
        connection_result.append(reason_code)
        connected.set()

    def on_publish(client, userdata, mid, reason_code, properties):
        publish_results[mid] = reason_code

    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"nixos-ci-{uuid.uuid4().hex}",
        protocol=mqtt.MQTTv5,
        transport="websockets",
    )
    client.username_pw_set("nixos-deploy-ci", os.environ["MQTT_NOTIFY_PASSWORD"])
    client.tls_set()
    client.ws_set_options(path="/socket")
    client.connect_timeout = 10
    client.on_connect = on_connect
    client.on_publish = on_publish
    client.connect("mqtt.jetersen.dev", 443, keepalive=30)
    client.loop_start()
    try:
        if not connected.wait(20) or connection_result[0].is_failure:
            raise RuntimeError("MQTT broker did not accept the CI connection")
        for host in ("framework", "rocket"):
            info = client.publish(f"{host}/button/update/command", "PRESS", qos=1, retain=False)
            info.wait_for_publish(timeout=20)
            if not info.is_published() or publish_results[info.mid].is_failure:
                raise RuntimeError(f"MQTT broker did not accept the {host} update hint")
            print(f"MQTT broker acknowledged the {host} deployment hint.", flush=True)
    finally:
        client.disconnect()
        client.loop_stop()


if __name__ == "__main__":
    main()
