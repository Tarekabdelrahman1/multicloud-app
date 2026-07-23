.RECIPEPREFIX := >

PYTHON := .venv/bin/python
PIP := .venv/bin/pip
PYTEST := .venv/bin/pytest
RUFF := .venv/bin/ruff
UVICORN := .venv/bin/uvicorn
ALEMBIC := .venv/bin/alembic

.PHONY: install run test lint format migrate seed compose-up compose-down docker-build clean

install:
>python3 -m venv .venv
>$(PIP) install --upgrade pip
>$(PIP) install -r requirements-dev.txt

run:
>$(UVICORN) app.main:app --host 0.0.0.0 --port 8080 --reload

test:
>$(PYTEST)

lint:
>$(RUFF) check .

format:
>$(RUFF) format .
>$(RUFF) check . --fix

migrate:
>$(ALEMBIC) upgrade head

seed:
>$(PYTHON) -m scripts.seed

compose-up:
>docker compose up --build -d

compose-down:
>docker compose down

docker-build:
>docker build -t device-service:local .

clean:
>rm -rf .pytest_cache .ruff_cache .coverage htmlcov
>find . -type d -name __pycache__ -prune -exec rm -rf {} +
