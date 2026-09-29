import os

import httpx
import pytest


BASE_URL = os.getenv(
    "BASE_URL",
    "http://127.0.0.1:8000"
)


def clear_tasks():
    response = httpx.get(
        f"{BASE_URL}/tasks",
        timeout=10
    )
    response.raise_for_status()

    for task in response.json():
        delete_response = httpx.delete(
            f"{BASE_URL}/tasks/{task['id']}",
            timeout=10
        )

        assert delete_response.status_code == 204


@pytest.fixture(autouse=True)
def clean_tasks():
    clear_tasks()

    yield

    clear_tasks()


def test_health_endpoint():
    response = httpx.get(
        f"{BASE_URL}/health",
        timeout=10
    )

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_create_and_list_task():
    create_response = httpx.post(
        f"{BASE_URL}/tasks",
        json={"title": "Integration Test"},
        timeout=10
    )

    assert create_response.status_code == 201

    created_task = create_response.json()

    assert created_task["title"] == "Integration Test"
    assert created_task["completed"] is False

    list_response = httpx.get(
        f"{BASE_URL}/tasks",
        timeout=10
    )

    assert list_response.status_code == 200

    tasks = list_response.json()

    assert len(tasks) == 1
    assert tasks[0]["title"] == "Integration Test"


def test_update_task_status():
    create_response = httpx.post(
        f"{BASE_URL}/tasks",
        json={"title": "Complete integration test"},
        timeout=10
    )

    task_id = create_response.json()["id"]

    response = httpx.patch(
        f"{BASE_URL}/tasks/{task_id}",
        json={"completed": True},
        timeout=10
    )

    assert response.status_code == 200
    assert response.json()["completed"] is True


def test_delete_task():
    create_response = httpx.post(
        f"{BASE_URL}/tasks",
        json={"title": "Delete integration test"},
        timeout=10
    )

    task_id = create_response.json()["id"]

    delete_response = httpx.delete(
        f"{BASE_URL}/tasks/{task_id}",
        timeout=10
    )

    assert delete_response.status_code == 204

    list_response = httpx.get(
        f"{BASE_URL}/tasks",
        timeout=10
    )

    assert list_response.json() == []


def test_empty_task_title_returns_400():
    response = httpx.post(
        f"{BASE_URL}/tasks",
        json={"title": "   "},
        timeout=10
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Task title is required"


def test_missing_task_returns_404():
    response = httpx.patch(
        f"{BASE_URL}/tasks/999999999",
        json={"completed": True},
        timeout=10
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"