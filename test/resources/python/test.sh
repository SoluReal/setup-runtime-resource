python --version | assert_contains "Python 3.12."
python3 --version | assert_contains "Python 3.12."

# pip is the interpreter's own, so an EXTERNALLY-MANAGED marker would fail this install.
cd "$PROJECTS/python"

pip install -r requirements.txt

export PYTHONPATH=$PYTHONPATH:$(pwd)/src
pytest
