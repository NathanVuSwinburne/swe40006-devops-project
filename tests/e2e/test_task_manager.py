import os

import httpx
import pytest
from playwright.sync_api import Page, expect


BASE_URL = os.getenv(
    "BASE_URL",
    "http://127.0.0.1:8000"
)


@pytest.fixture(autouse=True)
def clean_tasks():
    # Clean all existing tasks before each E2E test
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

    yield

    # Clean all tasks again after each E2E test
    response = httpx.get(
        f"{BASE_URL}/tasks",
        timeout=10
    )
    response.raise_for_status()

    for task in response.json():
        httpx.delete(
            f"{BASE_URL}/tasks/{task['id']}",
            timeout=10
        )


def add_task(page: Page, title: str):
    page.goto(BASE_URL)

    page.get_by_placeholder("Enter a task").fill(title)

    page.get_by_role(
        "button",
        name="Add task"
    ).click()

    expect(
        page.get_by_text(
            title,
            exact=True
        )
    ).to_be_visible()


def test_homepage_loads(page: Page):
    page.goto(BASE_URL)

    expect(
        page.get_by_role(
            "heading",
            name="SWE40006 Task Manager"
        )
    ).to_be_visible()


def test_create_task(page: Page):
    title = "Playwright deployment test"

    add_task(page, title)

    expect(
        page.get_by_text(
            title,
            exact=True
        )
    ).to_be_visible()


def test_complete_task(page: Page):
    title = "Complete E2E task"

    add_task(page, title)

    task = page.locator("li").filter(
        has_text=title
    )

    task.locator(
        'input[type="checkbox"]'
    ).check()

    expect(
        task.locator("span")
    ).to_have_class("completed")


def test_delete_task(page: Page):
    title = "Delete E2E task"

    add_task(page, title)

    task = page.locator("li").filter(
        has_text=title
    )

    task.get_by_role(
        "button",
        name="Delete"
    ).click()

    expect(
        page.get_by_text(
            title,
            exact=True
        )
    ).not_to_be_visible()


    