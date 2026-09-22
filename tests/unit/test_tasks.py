import pytest
from fastapi import HTTPException

import src.main as main


@pytest.fixture(autouse=True)
def reset_tasks():
    main.tasks.clear()
    main.next_task_id = 1

    yield

    main.tasks.clear()
    main.next_task_id = 1


def test_create_task():
    task = main.create_task(
        main.TaskCreate(title="Test deployment")
    )

    assert task["id"] == 1
    assert task["title"] == "Test deployment"
    assert task["completed"] is False


def test_create_task_trims_whitespace():
    task = main.create_task(
        main.TaskCreate(title="  Staging test  ")
    )

    assert task["title"] == "Staging test"


def test_create_task_rejects_empty_title():
    with pytest.raises(HTTPException) as error:
        main.create_task(
            main.TaskCreate(title="   ")
        )

    assert error.value.status_code == 400
    assert error.value.detail == "Task title is required"


def test_find_existing_task():
    created = main.create_task(
        main.TaskCreate(title="Find me")
    )

    found = main.find_task(created["id"])

    assert found == created


def test_find_missing_task_returns_404():
    with pytest.raises(HTTPException) as error:
        main.find_task(999)

    assert error.value.status_code == 404
    assert error.value.detail == "Task not found"


def test_update_task_status():
    task = main.create_task(
        main.TaskCreate(title="Complete me")
    )

    updated = main.update_task_status(
        task["id"],
        main.TaskStatusUpdate(completed=True),
    )

    assert updated["completed"] is True