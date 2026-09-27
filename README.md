# swe40006-devops-project
SWE40006 Final DevOps Group Project

## Run the Task Manager locally

Copy `.env.example` to `.env` and replace its sample password with a unique local password. Then run:

```sh
docker compose up --build -d
```

Open http://localhost:8000/ for the Task Manager, or http://localhost:8000/health for the health response. PostgreSQL data is stored in the `postgres_data` Docker volume and remains after the app restarts. Run `docker compose down` to stop both containers without deleting the data.

For a direct Python run, install `requirements.txt` and set the standard PostgreSQL connection environment variables `PGHOST`, `PGDATABASE`, `PGUSER`, and `PGPASSWORD` before starting `uvicorn src.main:app`. The app creates its `tasks` table on startup.
