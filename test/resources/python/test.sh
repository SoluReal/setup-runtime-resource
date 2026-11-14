cd "$PROJECTS/python"

pyenv install --skip-existing

pip install -r requirements.txt

export PYTHONPATH=$PYTHONPATH:$(pwd)/src
pytest
