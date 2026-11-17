python --version | assert_contains "Python 3.12."
python3 --version | assert_contains "Python 3.12."

# The interpreter is externally managed (PEP 668), so packages go into a venv.
cd "$PROJECTS/python"
uv venv
uv pip install -r requirements.txt
PYTHONPATH="$(pwd)/src" uv run pytest
