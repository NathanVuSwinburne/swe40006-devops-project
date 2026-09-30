# swe40006-devops-project
SWE40006 Final DevOps Group Project

## Run the Task Manager locally

Copy `.env.example` to `.env` and replace its sample password with a unique local password. Then run:

```sh
docker compose up --build -d
```

Open http://localhost:8000/ for the Task Manager, or http://localhost:8000/health for the health response. PostgreSQL data is stored in the `postgres_data` Docker volume and remains after the app restarts. Run `docker compose down` to stop both containers without deleting the data.

For a direct Python run, install `requirements.txt` and set the standard PostgreSQL connection environment variables `PGHOST`, `PGDATABASE`, `PGUSER`, and `PGPASSWORD` before starting `uvicorn src.main:app`. The app creates its `tasks` table on startup.

## Run the full test suite locally

From the repository root, create and activate a Python virtual environment (for example, `python -m venv .venv` and `.venv\Scripts\Activate.ps1` in PowerShell), then run:

```sh
python -m pip install -r requirements.txt
python -m playwright install chromium
```

Start the local PostgreSQL and API services with `docker compose up --build -d` as described above. Once `http://127.0.0.1:8000/health` responds, run:

```sh
python -m pytest -v
```

The integration, staging, and browser tests use the running API at `http://127.0.0.1:8000` by default. Set `BASE_URL` if the API is hosted elsewhere.
