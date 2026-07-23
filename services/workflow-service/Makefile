.RECIPEPREFIX := >

.PHONY: install run test lint

install:
>python3 -m venv .venv
>.venv/bin/pip install --upgrade pip
>.venv/bin/pip install -r requirements-dev.txt

run:
>.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload

test:
>.venv/bin/pytest

lint:
>.venv/bin/ruff check .
