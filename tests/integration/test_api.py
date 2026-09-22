import pytest
from fastapi.testclient import TestClient

import src.main as main


client = TestClient(main.app)


@pytest.fixture(autouse=True)
def reset_tasks():
    main.tasks.clear()
    main.next_task_id = 1

    yield

    main.tasks.clear()
    main.next_task_id = 1


def test_health_endpoint():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_create_and_list_task():
    create_response = client.post(
        "/tasks",
        json={"title": "Integration Test"},
    )

    assert create_response.status_code == 201

    created_task = create_response.json()

    assert created_task["title"] == "Integration Test"
    assert created_task["completed"] is False

    list_response = client.get("/tasks")

    assert list_response.status_code == 200

    tasks = list_response.json()

    assert len(tasks) == 1
    assert tasks[0]["title"] == "Integration Test"


def test_update_task_status():
    create_response = client.post(
        "/tasks",
        json={"title": "Complete integration test"},
    )

    task_id = create_response.json()["id"]

    response = client.patch(
        f"/tasks/{task_id}",
        json={"completed": True},
    )

    assert response.status_code == 200
    assert response.json()["completed"] is True


def test_delete_task():
    create_response = client.post(
        "/tasks",
        json={"title": "Delete integration test"},
    )

    task_id = create_response.json()["id"]

    delete_response = client.delete(
        f"/tasks/{task_id}"
    )

    assert delete_response.status_code == 204

    list_response = client.get("/tasks")

    assert list_response.json() == []


def test_empty_task_title_returns_400():
    response = client.post(
        "/tasks",
        json={"title": "   "},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Task title is required"


def test_missing_task_returns_404():
    response = client.patch(
        "/tasks/999",
        json={"completed": True},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"
    