import os
import httpx


BASE_URL = os.getenv(
    "BASE_URL",
    "http://127.0.0.1:8000"
)


def test_staging_health():
    response = httpx.get(
        f"{BASE_URL}/health",
        timeout=10
    )

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_staging_task_crud():
    create_response = httpx.post(
        f"{BASE_URL}/tasks",
        json={"title": "Staging integration test"},
        timeout=10
    )

    assert create_response.status_code == 201

    task = create_response.json()
    task_id = task["id"]

    assert task["title"] == "Staging integration test"
    assert task["completed"] is False

    update_response = httpx.patch(
        f"{BASE_URL}/tasks/{task_id}",
        json={"completed": True},
        timeout=10
    )

    assert update_response.status_code == 200
    assert update_response.json()["completed"] is True

    delete_response = httpx.delete(
        f"{BASE_URL}/tasks/{task_id}",
        timeout=10
    )

    assert delete_response.status_code == 204

    