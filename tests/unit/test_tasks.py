from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

import src.main as main


@pytest.fixture
def mock_db(monkeypatch):
    connection = MagicMock()

    context_manager = MagicMock()
    context_manager.__enter__.return_value = connection
    context_manager.__exit__.return_value = False

    monkeypatch.setattr(
        main,
        "database_connection",
        lambda: context_manager,
    )

    return connection


def test_create_task(mock_db):
    expected_task = {
        "id": 1,
        "title": "Test deployment",
        "completed": False,
    }

    mock_db.execute.return_value.fetchone.return_value = expected_task

    task = main.create_task(
        main.TaskCreate(title="Test deployment")
    )

    assert task == expected_task

    _, parameters = mock_db.execute.call_args.args
    assert parameters == ("Test deployment",)


def test_create_task_trims_whitespace(mock_db):
    expected_task = {
        "id": 1,
        "title": "Staging test",
        "completed": False,
    }

    mock_db.execute.return_value.fetchone.return_value = expected_task

    task = main.create_task(
        main.TaskCreate(title="  Staging test  ")
    )

    assert task["title"] == "Staging test"

    _, parameters = mock_db.execute.call_args.args
    assert parameters == ("Staging test",)


def test_create_task_rejects_empty_title(mock_db):
    with pytest.raises(HTTPException) as error:
        main.create_task(
            main.TaskCreate(title="   ")
        )

    assert error.value.status_code == 400
    assert error.value.detail == "Task title is required"

    mock_db.execute.assert_not_called()


def test_list_tasks(mock_db):
    expected_tasks = [
        {
            "id": 1,
            "title": "Task one",
            "completed": False,
        }
    ]

    mock_db.execute.return_value.fetchall.return_value = expected_tasks

    tasks = main.list_tasks()

    assert tasks == expected_tasks


def test_missing_task_returns_404(mock_db):
    mock_db.execute.return_value.fetchone.return_value = None

    with pytest.raises(HTTPException) as error:
        main.update_task_status(
            999,
            main.TaskStatusUpdate(completed=True),
        )

    assert error.value.status_code == 404
    assert error.value.detail == "Task not found"


def test_update_task_status(mock_db):
    expected_task = {
        "id": 1,
        "title": "Complete me",
        "completed": True,
    }

    mock_db.execute.return_value.fetchone.return_value = expected_task

    updated = main.update_task_status(
        1,
        main.TaskStatusUpdate(completed=True),
    )

    assert updated["completed"] is True

    _, parameters = mock_db.execute.call_args.args
    assert parameters == (True, 1)
    