from fastapi import FastAPI, HTTPException, Response, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel


app = FastAPI()

tasks: list[dict[str, object]] = []
next_task_id = 1


class TaskCreate(BaseModel):
    title: str


class TaskStatusUpdate(BaseModel):
    completed: bool


@app.get("/", response_class=HTMLResponse)
def read_home() -> str:
    return """
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SWE40006 Task Manager</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 680px; margin: 48px auto; padding: 0 20px; color: #1f2937; }
        h1 { margin-bottom: 8px; }
        p { color: #4b5563; }
        form, li { display: flex; gap: 10px; margin: 16px 0; }
        input[type="text"] { flex: 1; padding: 10px; }
        button { padding: 8px 12px; cursor: pointer; }
        ul { list-style: none; padding: 0; }
        li { align-items: center; padding: 12px; border: 1px solid #d1d5db; border-radius: 6px; }
        li span { flex: 1; }
        .completed { text-decoration: line-through; color: #6b7280; }
    </style>
</head>
<body>
    <h1>SWE40006 Task Manager</h1>
    <p>Create a task, mark it complete, or delete it.</p>
    <form id="task-form">
        <input id="task-title" type="text" placeholder="Enter a task" required>
        <button type="submit">Add task</button>
    </form>
    <ul id="task-list"></ul>

    <script>
        const taskList = document.querySelector("#task-list");
        const taskForm = document.querySelector("#task-form");
        const taskTitle = document.querySelector("#task-title");

        async function loadTasks() {
            const response = await fetch("/tasks");
            const tasks = await response.json();
            taskList.replaceChildren();

            for (const task of tasks) {
                const item = document.createElement("li");
                const checkbox = document.createElement("input");
                const title = document.createElement("span");
                const deleteButton = document.createElement("button");

                checkbox.type = "checkbox";
                checkbox.checked = task.completed;
                checkbox.addEventListener("change", async () => {
                    await fetch(`/tasks/${task.id}`, {
                        method: "PATCH",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ completed: checkbox.checked })
                    });
                    loadTasks();
                });

                title.textContent = task.title;
                if (task.completed) title.className = "completed";

                deleteButton.textContent = "Delete";
                deleteButton.addEventListener("click", async () => {
                    await fetch(`/tasks/${task.id}`, { method: "DELETE" });
                    loadTasks();
                });

                item.append(checkbox, title, deleteButton);
                taskList.append(item);
            }
        }

        taskForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            await fetch("/tasks", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ title: taskTitle.value })
            });
            taskTitle.value = "";
            loadTasks();
        });

        loadTasks();
    </script>
</body>
</html>
"""


@app.get("/tasks")
def list_tasks() -> list[dict[str, object]]:
    return tasks


@app.post("/tasks", status_code=status.HTTP_201_CREATED)
def create_task(task: TaskCreate) -> dict[str, object]:
    global next_task_id

    title = task.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Task title is required")

    new_task: dict[str, object] = {
        "id": next_task_id,
        "title": title,
        "completed": False,
    }
    tasks.append(new_task)
    next_task_id += 1
    return new_task


def find_task(task_id: int) -> dict[str, object]:
    for task in tasks:
        if task["id"] == task_id:
            return task
    raise HTTPException(status_code=404, detail="Task not found")


@app.patch("/tasks/{task_id}")
def update_task_status(
    task_id: int, update: TaskStatusUpdate
) -> dict[str, object]:
    task = find_task(task_id)
    task["completed"] = update.completed
    return task


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int) -> Response:
    task = find_task(task_id)
    tasks.remove(task)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/health")
def read_health() -> dict[str, str]:
    return {"status": "healthy"}
