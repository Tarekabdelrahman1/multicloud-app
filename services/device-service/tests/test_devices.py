from fastapi.testclient import TestClient


def payload() -> dict[str, str]:
    return {
        "hostname": "cairo-core-01",
        "management_ip": "10.10.0.11",
        "vendor": "nokia",
        "model": "7750 SR-1",
        "site": "Cairo-Core",
        "software_version": "24.7.R1",
        "status": "active",
    }


def test_device_crud(client: TestClient) -> None:
    created = client.post("/api/v1/devices", json=payload())
    assert created.status_code == 201
    device_id = created.json()["id"]

    listed = client.get("/api/v1/devices")
    assert listed.status_code == 200
    assert listed.json()["total"] == 1

    updated = client.patch(
        f"/api/v1/devices/{device_id}",
        json={"status": "maintenance"},
    )
    assert updated.status_code == 200
    assert updated.json()["status"] == "maintenance"

    deleted = client.delete(f"/api/v1/devices/{device_id}")
    assert deleted.status_code == 204

    missing = client.get(f"/api/v1/devices/{device_id}")
    assert missing.status_code == 404


def test_duplicate_hostname_returns_conflict(client: TestClient) -> None:
    assert client.post("/api/v1/devices", json=payload()).status_code == 201
    duplicate = payload()
    duplicate["management_ip"] = "10.10.0.12"
    response = client.post("/api/v1/devices", json=duplicate)
    assert response.status_code == 409
